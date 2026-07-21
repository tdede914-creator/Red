"""Pakasir payment gateway client — polling-based (no webhook).

Adapted from the pattern used in the user's own BOTRDP bot
(`src/utils/paymentGateway.js`). Instead of exposing a webhook endpoint,
we poll `/api/transactiondetail` from the bot side, which:

    - Removes the need for a public HTTPS domain
    - Removes the need for a reverse proxy / TLS certificate
    - Works even if the bot is behind NAT

Supported methods:
    - createPayment(method, order_id, amount)
    - detailPayment(order_id, amount)       ← used by the polling loop
    - getPaymentUrl(...)                    ← local URL builder
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Literal, Optional
from urllib.parse import quote

import httpx

from .config import settings

log = logging.getLogger(__name__)

PaymentMethod = Literal[
    "qris", "paypal",
    "cimb_niaga_va", "bni_va", "sampoerna_va", "bnc_va",
    "maybank_va", "permata_va", "atm_bersama_va", "artha_graha_va",
    "bri_va",
]

PaymentStatus = Literal[
    "pending", "canceled", "cancelled", "completed",
    "success", "failed", "expired", "settlement", "paid",
]


@dataclass
class PaymentPayload:
    """Normalized payment info — shape mirrors BOTRDP's paymentGateway.js."""
    project: str
    order_id: str
    amount: int
    fee: int
    status: str
    total_payment: int
    payment_method: str
    payment_number: Optional[str] = None
    payment_url: Optional[str] = None
    qr_string: Optional[str] = None
    qr_image: Optional[str] = None
    expired_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    raw: Optional[dict[str, Any]] = None


class PakasirError(Exception):
    """Raised on API failures or invalid input."""


def sanitize_order_id(order_id: str) -> str:
    """Match SDK's sanitizeUrlSafe: keep alnum, dash, underscore only."""
    return re.sub(r"[^A-Za-z0-9_-]", "", order_id)


def _calc_fee(method: str, amount: int) -> int:
    """Fee calculation matching the TS SDK."""
    if method == "qris":
        return round(0.01 * amount) if amount > 105_000 else round(0.007 * amount + 310)
    if method == "paypal":
        if amount < 10_000:
            raise PakasirError("PayPal minimum amount is Rp10.000")
        return max(round(0.01 * amount), 3_000)
    va_3500 = {"cimb_niaga_va", "bni_va", "bnc_va", "maybank_va",
               "permata_va", "atm_bersama_va", "bri_va"}
    va_2000 = {"sampoerna_va", "artha_graha_va"}
    if method in va_3500:
        return 3_500
    if method in va_2000:
        return 2_000
    return 0


def _parse_iso(dt_str: Any) -> Optional[datetime]:
    """Best-effort ISO 8601 parsing."""
    if not isinstance(dt_str, str) or not dt_str:
        return None
    try:
        return datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
    except ValueError:
        return None


class Pakasir:
    """Async Pakasir client. Instantiate once per operation or reuse."""

    def __init__(
        self,
        slug: str,
        api_key: str,
        base_url: Optional[str] = None,
        timeout: float = 30.0,
    ):
        if not slug or not api_key:
            raise PakasirError("Pakasir slug and api_key are required")
        self.slug = slug
        self.api_key = api_key
        base = (base_url or settings.pakasir_base_url).rstrip("/")
        self._base_url = base
        self._client = httpx.AsyncClient(timeout=timeout, base_url=base)

    async def close(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> "Pakasir":
        return self

    async def __aexit__(self, *args) -> None:
        await self.close()

    # ── Local URL builder (no network call) ─────────────────────────
    def get_payment_url(
        self,
        method: PaymentMethod,
        order_id: str,
        amount: int,
        redirect_url: Optional[str] = None,
    ) -> PaymentPayload:
        order_id = sanitize_order_id(order_id)
        if len(order_id) < 5:
            raise PakasirError("Order ID must be at least 5 characters")
        if amount < 500:
            raise PakasirError("Amount must be at least Rp500")

        fee = _calc_fee(method, amount)
        expired_at = datetime.now(timezone.utc) + timedelta(hours=24)

        redirect_param = quote(redirect_url) if redirect_url else ""
        oid = quote(order_id)
        slug = quote(self.slug)
        if method == "qris":
            url = (
                f"{self._base_url}/pay/{slug}/{amount}"
                f"?order_id={oid}&redirect={redirect_param}&qris_only=1"
            )
        elif method == "paypal":
            url = (
                f"{self._base_url}/paypal/{slug}/{amount}"
                f"?order_id={oid}&redirect={redirect_param}"
            )
        else:  # VA
            url = (
                f"{self._base_url}/pay/{slug}/{amount}"
                f"?order_id={oid}&redirect={redirect_param}&payment_method={method}"
            )

        return PaymentPayload(
            project=self.slug,
            order_id=order_id,
            amount=amount,
            fee=fee,
            status="pending",
            total_payment=amount + fee,
            payment_method=method,
            payment_url=url,
            expired_at=expired_at,
        )

    # ── API: create payment ─────────────────────────────────────────
    async def create_payment(
        self,
        method: PaymentMethod,
        order_id: str,
        amount: int,
        redirect_url: Optional[str] = None,
    ) -> PaymentPayload:
        base = self.get_payment_url(method, order_id, amount, redirect_url)

        body = {
            "project": self.slug,
            "api_key": self.api_key,
            "order_id": base.order_id,
            "amount": base.amount,
        }
        # Some Pakasir accounts accept extra fields; include them defensively
        if redirect_url:
            body["redirect_url"] = redirect_url

        try:
            r = await self._client.post(
                f"/api/transactioncreate/{quote(method)}",
                json=body,
                headers={"Content-Type": "application/json"},
            )
            r.raise_for_status()
            data = r.json()
        except httpx.HTTPError as e:
            body_text = ""
            if isinstance(e, httpx.HTTPStatusError):
                body_text = f" | body={e.response.text[:200]}"
            raise PakasirError(
                f"HTTP error during create_payment: {e}{body_text}"
            ) from e

        pay = data.get("payment") or data.get("transaction") or data.get("data") or data or {}
        base.raw = data
        base.payment_number = (
            pay.get("payment_number")
            or pay.get("qr_string")
            or pay.get("qris_string")
            or pay.get("qr_payload")
        )
        base.qr_string = pay.get("qr_string") or pay.get("qris_string") or pay.get("qr_payload")
        base.qr_image = pay.get("qr_image") or pay.get("qr_url") or pay.get("qris_url")
        base.payment_url = (
            pay.get("payment_url") or pay.get("paymentUrl")
            or pay.get("checkout_url") or base.payment_url
        )
        if exp := _parse_iso(pay.get("expired_at")):
            base.expired_at = exp
        if pay.get("fee"):
            try:
                base.fee = int(pay["fee"])
                base.total_payment = base.amount + base.fee
            except (TypeError, ValueError):
                pass

        return base

    # ── API: detail (used by polling loop) ──────────────────────────
    async def detail_payment(self, order_id: str, amount: int) -> PaymentPayload:
        order_id = sanitize_order_id(order_id)
        params = {
            "project": self.slug,
            "amount": amount,
            "order_id": order_id,
            "api_key": self.api_key,
        }
        try:
            r = await self._client.get("/api/transactiondetail", params=params)
            r.raise_for_status()
            data = r.json()
        except httpx.HTTPError as e:
            raise PakasirError(f"HTTP error during detail_payment: {e}") from e

        trx = data.get("transaction") or data.get("payment") or data.get("data") or data or {}
        method = trx.get("payment_method", settings.pakasir_method)

        base = self.get_payment_url(method, order_id, amount)  # type: ignore[arg-type]
        base.raw = data
        base.status = trx.get("status", "pending")
        if completed := _parse_iso(trx.get("completed_at") or trx.get("paid_at")):
            base.completed_at = completed
        if exp := _parse_iso(trx.get("expired_at")):
            base.expired_at = exp
        base.qr_image = trx.get("qr_image") or trx.get("qr_url") or base.qr_image
        base.qr_string = trx.get("qr_string") or trx.get("qris_string") or base.qr_string
        return base

"""Pakasir payment gateway client — Python port of `pakasir-sdk`.

Reference: https://github.com/zeative/pakasir-sdk (TypeScript SDK).
Only synchronous HTTP calls; we use httpx.AsyncClient for concurrency.

Supported methods:
    - createPayment(method, order_id, amount, redirect_url)
    - detailPayment(order_id, amount)
    - cancelPayment(order_id, amount)
    - simulationPayment(order_id, amount)  # sandbox testing
    - getPaymentUrl(...)                    # local URL builder (no API call)

Webhook payloads must be verified with the shared PAKASIR_WEBHOOK_SECRET.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional

import httpx

log = logging.getLogger(__name__)

BASE_API_URL = "https://app.pakasir.com"

PaymentMethod = Literal[
    "all", "qris", "paypal",
    "cimb_niaga_va", "bni_va", "sampoerna_va", "bnc_va",
    "maybank_va", "permata_va", "atm_bersama_va", "artha_graha_va",
    "bri_va",
]

PaymentStatus = Literal["pending", "canceled", "completed"]


@dataclass
class PaymentPayload:
    project: str
    order_id: str
    amount: int
    fee: int
    status: PaymentStatus
    total_payment: int
    payment_method: str
    payment_number: Optional[str] = None
    payment_url: Optional[str] = None
    redirect_url: Optional[str] = None
    expired_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


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
    return 0  # 'all' or unknown → fee resolved server-side


class Pakasir:
    """Async Pakasir client. Instantiate once and reuse."""

    def __init__(self, slug: str, api_key: str, timeout: float = 15.0):
        if not slug or not api_key:
            raise PakasirError("Pakasir slug and api_key are required")
        self.slug = slug
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=timeout, base_url=BASE_API_URL)

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

        redirect_param = redirect_url or ""
        if method == "all":
            url = f"{BASE_API_URL}/pay/{self.slug}/{amount}?order_id={order_id}&redirect={redirect_param}"
        elif method == "qris":
            url = (
                f"{BASE_API_URL}/pay/{self.slug}/{amount}"
                f"?order_id={order_id}&redirect={redirect_param}&qris_only=1"
            )
        elif method == "paypal":
            url = f"{BASE_API_URL}/paypal/{self.slug}/{amount}?order_id={order_id}&redirect={redirect_param}"
        else:  # VA
            url = (
                f"{BASE_API_URL}/pay/{self.slug}/{amount}"
                f"?order_id={order_id}&redirect={redirect_param}&payment_method={method}"
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
            redirect_url=redirect_url,
            expired_at=expired_at,
        )

    # ── API: create ─────────────────────────────────────────────────
    async def create_payment(
        self,
        method: PaymentMethod,
        order_id: str,
        amount: int,
        redirect_url: Optional[str] = None,
    ) -> PaymentPayload:
        payload = self.get_payment_url(method, order_id, amount, redirect_url)
        body = {
            "project": payload.project,
            "api_key": self.api_key,
            "order_id": payload.order_id,
            "amount": payload.amount,
            "redirect_url": payload.redirect_url,
        }
        try:
            r = await self._client.post(f"/api/transactioncreate/{method}", json=body)
            r.raise_for_status()
            data = r.json()
        except httpx.HTTPError as e:
            raise PakasirError(f"HTTP error during create_payment: {e}") from e

        if not data.get("payment") and not data.get("data"):
            raise PakasirError(data.get("message", "Failed to create payment"))

        pay = data.get("payment", data.get("data", {}))
        payload.payment_number = pay.get("payment_number")
        exp = pay.get("expired_at")
        if exp:
            try:
                payload.expired_at = datetime.fromisoformat(exp.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                pass
        return payload

    # ── API: detail ─────────────────────────────────────────────────
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

        trx = data.get("transaction") or data.get("data")
        if not trx:
            raise PakasirError(data.get("message", "Failed to get payment detail"))

        method = trx.get("payment_method", "qris")
        base = self.get_payment_url(method, order_id, amount)
        base.status = trx.get("status", "pending")
        completed = trx.get("completed_at")
        if completed:
            try:
                base.completed_at = datetime.fromisoformat(completed.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                pass
        return base

    # ── API: cancel ─────────────────────────────────────────────────
    async def cancel_payment(self, order_id: str, amount: int) -> PaymentPayload:
        order_id = sanitize_order_id(order_id)
        body = {
            "project": self.slug,
            "api_key": self.api_key,
            "order_id": order_id,
            "amount": amount,
        }
        try:
            r = await self._client.post("/api/transactioncancel", json=body)
            r.raise_for_status()
            data = r.json()
        except httpx.HTTPError as e:
            raise PakasirError(f"HTTP error during cancel_payment: {e}") from e

        if not data.get("success") and not data.get("data"):
            raise PakasirError(data.get("message", "Failed to cancel payment"))

        payload = await self.detail_payment(order_id, amount)
        payload.status = "canceled"
        return payload

    # ── API: simulate (sandbox only) ────────────────────────────────
    async def simulate_payment(self, order_id: str, amount: int) -> PaymentPayload:
        order_id = sanitize_order_id(order_id)
        body = {
            "project": self.slug,
            "api_key": self.api_key,
            "order_id": order_id,
            "amount": amount,
        }
        try:
            r = await self._client.post("/api/paymentsimulation", json=body)
            r.raise_for_status()
            data = r.json()
        except httpx.HTTPError as e:
            raise PakasirError(f"HTTP error during simulate_payment: {e}") from e

        if not data.get("success") and not data.get("data"):
            raise PakasirError(data.get("message", "Failed to simulate payment"))

        payload = await self.detail_payment(order_id, amount)
        payload.status = "completed"
        return payload


# ── Webhook verification ────────────────────────────────────────────
def verify_webhook_signature(secret: str, raw_body: bytes, signature: str) -> bool:
    """Verify an HMAC-SHA256 signature in the `X-Pakasir-Signature` header.

    Pakasir doesn't officially document a signature scheme yet; we implement
    a conservative HMAC-SHA256 over the raw body using PAKASIR_WEBHOOK_SECRET.
    When Pakasir publishes their scheme, update this function to match.
    """
    if not secret or not signature:
        return False
    expected = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature.lower())

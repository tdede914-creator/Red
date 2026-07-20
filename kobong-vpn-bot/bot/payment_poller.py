"""Background polling task for pending Pakasir payments.

Pattern adapted from the BOTRDP `paymentTracker.js` + `paymentStatus.js`:
instead of exposing a webhook endpoint (which needs public HTTPS domain
and reverse proxy), we simply poll Pakasir's `/api/transactiondetail`
every N seconds until status flips to `completed` or `canceled`, then
auto-credit the user's balance.

Advantages over webhooks:
    - No public domain / TLS required
    - Works on VPS behind NAT
    - Simpler deployment (no Caddy / Nginx)

Tradeoff: one extra HTTP request per pending order every 10s. Trivial
even at hundreds of concurrent pending orders.

Concurrency model:
    * Poller owns one asyncio task per tracked order_ref.
    * A shared `_cancelled` set lets other handlers request early exit.
    * On bot startup, `start()` resumes polling for any orders left
      PENDING in the DB from a previous run (crash-safe).
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import select
from telegram import Bot

from .config import settings
from .db import get_session
from .models import Order, OrderStatus, User
from .pakasir import Pakasir, PakasirError

log = logging.getLogger(__name__)


class PaymentPoller:
    """Manages background polling for pending payments."""

    # Polling parameters — mirror the BOTRDP defaults
    POLL_INTERVAL = 10  # seconds between checks
    MAX_RETRIES = 60    # 60 × 10s = 10 minute window

    def __init__(self, bot: Bot):
        self.bot = bot
        self._tasks: dict[str, asyncio.Task] = {}
        self._cancelled: set[str] = set()
        self._lock = asyncio.Lock()

    # ── Lifecycle ────────────────────────────────────────────────────
    async def start(self) -> None:
        """Resume polling for any PENDING orders left in DB."""
        async with get_session() as session:
            result = await session.execute(
                select(Order).where(Order.status == OrderStatus.PENDING)
            )
            orders = list(result.scalars())

            resumed = 0
            for order in orders:
                user_result = await session.execute(
                    select(User).where(User.id == order.user_id)
                )
                user = user_result.scalar_one_or_none()
                if user is None:
                    continue
                self.track(order.order_ref, order.amount, user.telegram_id)
                resumed += 1

        log.info("Payment poller started: resumed %d pending order(s)", resumed)

    async def stop(self) -> None:
        """Cancel all polling tasks (called on shutdown)."""
        for task in self._tasks.values():
            task.cancel()
        # Give tasks a moment to clean up
        if self._tasks:
            await asyncio.gather(*self._tasks.values(), return_exceptions=True)
        self._tasks.clear()
        self._cancelled.clear()
        log.info("Payment poller stopped")

    # ── Public API ───────────────────────────────────────────────────
    def track(self, order_ref: str, amount: int, user_telegram_id: int) -> None:
        """Start polling this order in the background."""
        if order_ref in self._tasks and not self._tasks[order_ref].done():
            log.debug("Order %s already tracked", order_ref)
            return
        self._cancelled.discard(order_ref)
        self._tasks[order_ref] = asyncio.create_task(
            self._poll_loop(order_ref, amount, user_telegram_id),
            name=f"pay-poll:{order_ref}",
        )
        log.info(
            "Tracking order %s (amount=Rp%s, user=%s)",
            order_ref, f"{amount:,}", user_telegram_id,
        )

    def cancel(self, order_ref: str) -> None:
        """Mark an order as cancelled — polling loop will exit at next tick."""
        self._cancelled.add(order_ref)
        task = self._tasks.get(order_ref)
        if task and not task.done():
            task.cancel()
        log.info("Cancelled polling for %s", order_ref)

    def is_tracking(self, order_ref: str) -> bool:
        task = self._tasks.get(order_ref)
        return task is not None and not task.done()

    # ── Internal poll loop ───────────────────────────────────────────
    async def _poll_loop(
        self, order_ref: str, amount: int, user_telegram_id: int
    ) -> None:
        # Initial delay: give user time to see QR/link before we start polling
        await asyncio.sleep(self.POLL_INTERVAL)

        try:
            async with Pakasir(settings.pakasir_slug, settings.pakasir_api_key) as pk:
                for attempt in range(1, self.MAX_RETRIES + 1):
                    if order_ref in self._cancelled:
                        log.info("Poll exit (cancelled): %s", order_ref)
                        return

                    try:
                        detail = await pk.detail_payment(order_ref, amount)
                    except PakasirError as e:
                        log.warning(
                            "Poll error %s [%d/%d]: %s",
                            order_ref, attempt, self.MAX_RETRIES, e,
                        )
                        await asyncio.sleep(self.POLL_INTERVAL)
                        continue

                    status = (detail.status or "").lower()
                    log.debug(
                        "Poll %s [%d/%d]: status=%s",
                        order_ref, attempt, self.MAX_RETRIES, status,
                    )

                    # Success statuses (match BOTRDP's `successStatuses`)
                    if status in {"completed", "success", "settlement", "paid", "capture"}:
                        await self._on_success(order_ref, amount, user_telegram_id)
                        return

                    # Failure / cancel statuses
                    if status in {"canceled", "cancelled", "failed", "expired", "deny", "error"}:
                        await self._on_canceled(order_ref, amount, user_telegram_id, status)
                        return

                    # Otherwise: pending / created / active — keep polling
                    await asyncio.sleep(self.POLL_INTERVAL)

                # Ran out of retries
                await self._on_timeout(order_ref, amount, user_telegram_id)

        except asyncio.CancelledError:
            log.info("Poll task cancelled: %s", order_ref)
            raise
        except Exception:
            log.exception("Unhandled error polling %s", order_ref)
        finally:
            async with self._lock:
                self._tasks.pop(order_ref, None)
                self._cancelled.discard(order_ref)

    # ── Terminal handlers ────────────────────────────────────────────
    async def _on_success(
        self, order_ref: str, amount: int, user_telegram_id: int
    ) -> None:
        # Idempotent: only credit if order is still PENDING
        credited = False
        new_balance = 0
        async with get_session() as session:
            order_result = await session.execute(
                select(Order).where(Order.order_ref == order_ref)
            )
            order = order_result.scalar_one_or_none()
            if not order or order.status != OrderStatus.PENDING:
                log.info("Order %s already handled (status=%s), skip credit",
                         order_ref, order.status.value if order else "missing")
                return

            order.status = OrderStatus.COMPLETED
            order.completed_at = datetime.now(timezone.utc)

            user_result = await session.execute(
                select(User).where(User.id == order.user_id)
            )
            user = user_result.scalar_one()
            user.balance += amount
            new_balance = user.balance
            credited = True

        if credited:
            log.info(
                "✅ Payment %s completed: user=%s +Rp%s (new: Rp%s)",
                order_ref, user_telegram_id, f"{amount:,}", f"{new_balance:,}",
            )
            await self._notify(
                user_telegram_id,
                (
                    f"✅ <b>Pembayaran Berhasil!</b>\n\n"
                    f"Ref: <code>{order_ref}</code>\n"
                    f"Nominal: <b>Rp {amount:,}</b>\n"
                    f"Saldo baru: <b>Rp {new_balance:,}</b>\n\n"
                    f"🎉 Terima kasih! Saldo sudah ditambahkan ke akun kamu."
                ),
            )

    async def _on_canceled(
        self, order_ref: str, amount: int, user_telegram_id: int, status: str
    ) -> None:
        async with get_session() as session:
            order_result = await session.execute(
                select(Order).where(Order.order_ref == order_ref)
            )
            order = order_result.scalar_one_or_none()
            if order and order.status == OrderStatus.PENDING:
                order.status = OrderStatus.CANCELED if status in {"canceled", "cancelled"} else OrderStatus.FAILED

        log.info("❌ Payment %s ended: status=%s", order_ref, status)
        await self._notify(
            user_telegram_id,
            (
                f"❌ <b>Pembayaran Gagal / Dibatalkan</b>\n\n"
                f"Ref: <code>{order_ref}</code>\n"
                f"Nominal: Rp {amount:,}\n"
                f"Status: <b>{status}</b>\n\n"
                f"Silakan coba lagi kalau kamu masih ingin top up."
            ),
        )

    async def _on_timeout(
        self, order_ref: str, amount: int, user_telegram_id: int
    ) -> None:
        async with get_session() as session:
            order_result = await session.execute(
                select(Order).where(Order.order_ref == order_ref)
            )
            order = order_result.scalar_one_or_none()
            if order and order.status == OrderStatus.PENDING:
                order.status = OrderStatus.EXPIRED

        log.info("⏰ Payment %s timeout after %d retries", order_ref, self.MAX_RETRIES)
        minutes = (self.POLL_INTERVAL * self.MAX_RETRIES) // 60
        await self._notify(
            user_telegram_id,
            (
                f"⏰ <b>Monitoring Pembayaran Berakhir</b>\n\n"
                f"Ref: <code>{order_ref}</code>\n"
                f"Nominal: Rp {amount:,}\n\n"
                f"Bot berhenti auto-cek setelah {minutes} menit. "
                f"Kalau kamu sudah bayar, klik <b>Cek Status</b> manual "
                f"atau hubungi admin.\n\n"
                f"Kalau belum bayar, silakan buat transaksi baru."
            ),
        )

    async def _notify(self, chat_id: int, text: str) -> None:
        try:
            await self.bot.send_message(chat_id=chat_id, text=text, parse_mode="HTML")
        except Exception as e:  # noqa: BLE001
            log.error("Failed to notify %s: %s", chat_id, e)

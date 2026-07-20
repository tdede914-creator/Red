"""aiohttp web server for receiving Pakasir payment callbacks.

Pakasir will POST to `PUBLIC_WEBHOOK_URL/pakasir` when a transaction status
changes. We verify the signature (if provided), look up the order, credit the
user, and send a Telegram notification.

Endpoints:
    GET  /health          → readiness probe
    POST /webhook/pakasir → payment status callback
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Optional

from aiohttp import web
from sqlalchemy import select
from telegram import Bot

from .config import settings
from .db import get_session
from .models import Order, OrderStatus, User
from .pakasir import verify_webhook_signature

log = logging.getLogger(__name__)


class WebhookServer:
    def __init__(self, bot: Bot):
        self.bot = bot
        self.app = web.Application()
        self.app.router.add_get("/health", self._health)
        self.app.router.add_post("/webhook/pakasir", self._pakasir_webhook)
        self._runner: Optional[web.AppRunner] = None

    async def _health(self, request: web.Request) -> web.Response:
        return web.json_response({"ok": True, "service": "kobong-vpn-bot"})

    async def _pakasir_webhook(self, request: web.Request) -> web.Response:
        raw = await request.read()
        signature = request.headers.get("X-Pakasir-Signature", "")

        # Verify signature if secret is configured. If Pakasir doesn't send
        # signatures yet, we still accept but log a warning.
        if settings.pakasir_webhook_secret and signature:
            if not verify_webhook_signature(
                settings.pakasir_webhook_secret, raw, signature
            ):
                log.warning("Rejected webhook with bad signature")
                return web.json_response({"ok": False, "error": "bad_signature"}, status=401)
        elif settings.pakasir_webhook_secret:
            log.warning("Webhook received without signature — accepting anyway")

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return web.json_response({"ok": False, "error": "bad_json"}, status=400)

        # Expected payload shape (based on Pakasir SDK docs):
        # { "order_id": "...", "amount": 10000, "status": "completed", ... }
        order_ref = payload.get("order_id")
        status = payload.get("status")
        if not order_ref or not status:
            return web.json_response({"ok": False, "error": "missing_fields"}, status=400)

        async with get_session() as session:
            result = await session.execute(select(Order).where(Order.order_ref == order_ref))
            order = result.scalar_one_or_none()
            if order is None:
                log.warning("Webhook for unknown order: %s", order_ref)
                return web.json_response({"ok": False, "error": "order_not_found"}, status=404)

            if status == "completed" and order.status == OrderStatus.PENDING:
                order.status = OrderStatus.COMPLETED
                order.completed_at = datetime.now(timezone.utc)

                # Credit user balance
                user_result = await session.execute(
                    select(User).where(User.id == order.user_id)
                )
                user = user_result.scalar_one()
                user.balance += order.amount
                telegram_id = user.telegram_id
                new_balance = user.balance
                amount = order.amount

                # Notify user via Telegram
                try:
                    await self.bot.send_message(
                        chat_id=telegram_id,
                        text=(
                            f"✅ <b>Pembayaran diterima!</b>\n\n"
                            f"Ref: <code>{order_ref}</code>\n"
                            f"Nominal: <b>Rp {amount:,}</b>\n"
                            f"Saldo baru: <b>Rp {new_balance:,}</b>"
                        ),
                        parse_mode="HTML",
                    )
                except Exception as e:  # noqa: BLE001
                    log.error("Failed to notify user %s: %s", telegram_id, e)

            elif status == "canceled":
                order.status = OrderStatus.CANCELED

        return web.json_response({"ok": True})

    async def start(self) -> None:
        self._runner = web.AppRunner(self.app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, settings.webhook_host, settings.webhook_port)
        await site.start()
        log.info(
            "Webhook server started on http://%s:%s",
            settings.webhook_host,
            settings.webhook_port,
        )

    async def stop(self) -> None:
        if self._runner:
            await self._runner.cleanup()
            self._runner = None

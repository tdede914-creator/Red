"""Payment flow using Pakasir gateway with polling (no webhook).

Flow (mirrors BOTRDP):
    1. User → 💰 Top Up Saldo → pick amount → pick method
    2. Bot calls Pakasir.create_payment() and stores an Order (status=pending)
    3. Bot starts a background poller task for this order (checks every 10s)
    4. User pays via the shown link/QR
    5. Poller detects `completed` on Pakasir side → auto-credits balance +
       sends Telegram notification
    6. User can also click "Cek Status" any time for immediate check
    7. User can click "Batalkan" to stop monitoring (poller exits)
"""
from __future__ import annotations

import logging
import secrets
from datetime import datetime, timezone

from sqlalchemy import select
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import CallbackQueryHandler, ContextTypes

from ..config import settings
from ..db import get_session
from ..keyboards import back_only, payment_confirm, payment_method_menu
from ..models import Order, OrderStatus, User
from ..pakasir import Pakasir, PakasirError
from ..payment_poller import PaymentPoller
from .start import get_or_create_user

log = logging.getLogger(__name__)


def _make_order_ref(user_id: int) -> str:
    """Unique order reference: KBG-<user_tg_id>-<8-char-random>."""
    return f"KBG-{user_id}-{secrets.token_hex(4).upper()}"


def _get_poller(context: ContextTypes.DEFAULT_TYPE) -> PaymentPoller | None:
    """Retrieve the shared payment poller from bot_data."""
    poller = context.application.bot_data.get("poller")
    return poller if isinstance(poller, PaymentPoller) else None


async def pay_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    parts = (q.data or "").split(":")
    if len(parts) < 2:
        return
    action = parts[1]

    user = await get_or_create_user(update)

    # ── Pick amount ──────────────────────────────────────────────────
    if action == "amount":
        raw = parts[2] if len(parts) > 2 else ""
        if raw == "custom":
            await q.edit_message_text(
                "<b>💵 Nominal Custom</b>\n\n"
                "🚧 Input nominal manual belum tersedia di M1.\n"
                "Pilih nominal preset dulu.",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
            return
        try:
            amount = int(raw)
        except ValueError:
            await q.edit_message_text("Nominal tidak valid.", reply_markup=back_only())
            return
        if amount < 500:
            await q.edit_message_text(
                "Minimal top-up Rp 500.", reply_markup=back_only()
            )
            return
        await q.edit_message_text(
            f"<b>💳 Pilih Metode Pembayaran</b>\n\n"
            f"Nominal: <b>Rp {amount:,}</b>\n"
            f"<i>(biaya admin akan ditambahkan sesuai metode)</i>",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_method_menu(amount),
        )
        return

    # ── Pick method → create Pakasir transaction ─────────────────────
    if action == "method":
        if len(parts) < 4:
            return
        method = parts[2]
        try:
            amount = int(parts[3])
        except ValueError:
            return

        if not settings.is_pakasir_enabled:
            await q.edit_message_text(
                "⚠️ Pakasir belum dikonfigurasi. Hubungi admin bot.",
                reply_markup=back_only(),
            )
            return

        order_ref = _make_order_ref(user.telegram_id)
        try:
            async with Pakasir(settings.pakasir_slug, settings.pakasir_api_key) as pk:
                payment = await pk.create_payment(
                    method=method,  # type: ignore[arg-type]
                    order_id=order_ref,
                    amount=amount,
                )
        except PakasirError as e:
            log.error("Pakasir create_payment error: %s", e)
            await q.edit_message_text(
                f"❌ Gagal buat transaksi:\n<code>{e}</code>",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
            return

        # Persist order
        async with get_session() as session:
            order = Order(
                order_ref=order_ref,
                user_id=user.id,
                amount=amount,
                payment_method=method,
                status=OrderStatus.PENDING,
                payment_url=payment.payment_url,
                payment_number=payment.payment_number,
                expired_at=payment.expired_at,
            )
            session.add(order)

        # Start background polling for this order
        poller = _get_poller(context)
        if poller:
            poller.track(order_ref, amount, user.telegram_id)

        fee_line = f"Biaya admin: Rp {payment.fee:,}\n" if payment.fee else ""
        exp_line = (
            f"Berlaku sampai: {payment.expired_at:%d %b %Y %H:%M} UTC\n"
            if payment.expired_at else ""
        )
        await q.edit_message_text(
            f"<b>💳 Transaksi Dibuat</b>\n\n"
            f"Ref: <code>{order_ref}</code>\n"
            f"Nominal: <b>Rp {amount:,}</b>\n"
            f"{fee_line}"
            f"Total bayar: <b>Rp {payment.total_payment:,}</b>\n"
            f"Metode: <b>{method.upper()}</b>\n"
            f"{exp_line}"
            f"\n💡 Bot otomatis cek status tiap 10 detik selama 10 menit. "
            f"Kalau sudah bayar, saldo langsung ditambahkan.\n\n"
            f"Klik tombol di bawah untuk bayar 👇",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_confirm(payment.payment_url or ""),
        )
        return

    # ── Manual status check ─────────────────────────────────────────
    if action == "check":
        async with get_session() as session:
            result = await session.execute(
                select(Order)
                .where(Order.user_id == user.id, Order.status == OrderStatus.PENDING)
                .order_by(Order.created_at.desc())
                .limit(1)
            )
            order = result.scalar_one_or_none()

        if order is None:
            await q.edit_message_text(
                "Tidak ada transaksi pending untuk dicek.",
                reply_markup=back_only(),
            )
            return

        try:
            async with Pakasir(settings.pakasir_slug, settings.pakasir_api_key) as pk:
                detail = await pk.detail_payment(order.order_ref, order.amount)
        except PakasirError as e:
            await q.edit_message_text(
                f"❌ Gagal cek status:\n<code>{e}</code>",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
            return

        status_l = (detail.status or "").lower()
        success_set = {"completed", "success", "settlement", "paid", "capture"}

        if status_l in success_set and order.status == OrderStatus.PENDING:
            # Credit immediately (idempotent with poller — first to write wins)
            async with get_session() as session:
                order_result = await session.execute(
                    select(Order).where(Order.order_ref == order.order_ref)
                )
                o = order_result.scalar_one_or_none()
                if o and o.status == OrderStatus.PENDING:
                    o.status = OrderStatus.COMPLETED
                    o.completed_at = datetime.now(timezone.utc)
                    user_result = await session.execute(
                        select(User).where(User.id == o.user_id)
                    )
                    u = user_result.scalar_one()
                    u.balance += o.amount

                    # Poller will also detect; stop its task explicitly
                    poller = _get_poller(context)
                    if poller:
                        poller.cancel(o.order_ref)

                    await q.edit_message_text(
                        f"✅ <b>Pembayaran Berhasil!</b>\n\n"
                        f"Ref: <code>{o.order_ref}</code>\n"
                        f"Nominal: <b>Rp {o.amount:,}</b>\n"
                        f"Saldo baru: <b>Rp {u.balance:,}</b>",
                        parse_mode=ParseMode.HTML,
                        reply_markup=back_only(),
                    )
                    return

        await q.edit_message_text(
            f"⏳ Status: <b>{detail.status or 'pending'}</b>\n"
            f"Ref: <code>{order.order_ref}</code>\n"
            f"Nominal: Rp {order.amount:,}\n\n"
            f"Bot masih auto-cek tiap 10 detik. Kalau sudah bayar, "
            f"tunggu maks 1 menit lalu klik cek ulang.",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_confirm(order.payment_url or ""),
        )
        return

    # ── User cancels ────────────────────────────────────────────────
    if action == "cancel":
        async with get_session() as session:
            result = await session.execute(
                select(Order)
                .where(Order.user_id == user.id, Order.status == OrderStatus.PENDING)
                .order_by(Order.created_at.desc())
                .limit(1)
            )
            order = result.scalar_one_or_none()
            if order:
                order.status = OrderStatus.CANCELED

        if order:
            poller = _get_poller(context)
            if poller:
                poller.cancel(order.order_ref)
            await q.edit_message_text(
                f"❌ Transaksi <code>{order.order_ref}</code> dibatalkan.",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
        else:
            await q.edit_message_text(
                "Tidak ada transaksi pending.", reply_markup=back_only()
            )
        return


def register(app) -> None:
    app.add_handler(CallbackQueryHandler(pay_router, pattern=r"^pay:"))

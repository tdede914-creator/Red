"""Payment flow using Pakasir gateway (M1 skeleton).

Flow:
    1. User → 💰 Top Up Saldo → pick amount → pick method
    2. Bot → Pakasir.create_payment → shows payment URL + QR
    3. Pakasir → webhook → updates Order.status = completed
    4. Bot → auto-credit User.balance

Full webhook receiver + credit logic will be finished in M4.
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
from .start import get_or_create_user

log = logging.getLogger(__name__)


def _make_order_ref(user_id: int) -> str:
    """Unique order reference: KBG-<user_id>-<8-char-random>."""
    return f"KBG-{user_id}-{secrets.token_hex(4).upper()}"


async def pay_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    parts = (q.data or "").split(":")
    if len(parts) < 2:
        return
    action = parts[1]

    user = await get_or_create_user(update)

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
        await q.edit_message_text(
            f"<b>💳 Pilih Metode Pembayaran</b>\n\n"
            f"Nominal: <b>Rp {amount:,}</b>\n"
            f"(biaya admin akan ditambahkan sesuai metode)",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_method_menu(amount),
        )
        return

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
                    redirect_url=f"https://t.me/{settings.bot_username}",
                )
        except PakasirError as e:
            log.error("Pakasir error: %s", e)
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

        fee_text = f"\nBiaya admin: Rp {payment.fee:,}" if payment.fee else ""
        await q.edit_message_text(
            f"<b>💳 Transaksi Dibuat</b>\n\n"
            f"Ref: <code>{order_ref}</code>\n"
            f"Nominal: <b>Rp {amount:,}</b>{fee_text}\n"
            f"Total bayar: <b>Rp {payment.total_payment:,}</b>\n"
            f"Metode: <b>{method.upper()}</b>\n"
            f"Berlaku sampai: {payment.expired_at:%d %b %H:%M} UTC\n\n"
            f"Klik tombol di bawah untuk bayar. Bot akan otomatis "
            f"kirim notifikasi ketika pembayaran berhasil.",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_confirm(payment.payment_url or ""),
        )
        return

    if action == "check":
        # Look up latest pending order for this user
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
                "Tidak ada transaksi pending.", reply_markup=back_only()
            )
            return

        try:
            async with Pakasir(settings.pakasir_slug, settings.pakasir_api_key) as pk:
                detail = await pk.detail_payment(order.order_ref, order.amount)
        except PakasirError as e:
            await q.edit_message_text(
                f"❌ Gagal cek status: {e}", reply_markup=back_only()
            )
            return

        if detail.status == "completed" and order.status == OrderStatus.PENDING:
            # Credit user
            async with get_session() as session:
                result = await session.execute(select(User).where(User.id == user.id))
                u = result.scalar_one()
                u.balance += order.amount
                order_result = await session.execute(
                    select(Order).where(Order.order_ref == order.order_ref)
                )
                o = order_result.scalar_one()
                o.status = OrderStatus.COMPLETED
                o.completed_at = datetime.now(timezone.utc)
            await q.edit_message_text(
                f"✅ <b>Pembayaran berhasil!</b>\n\n"
                f"Saldo bertambah: <b>Rp {order.amount:,}</b>",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
            return

        await q.edit_message_text(
            f"⏳ Status: <b>{detail.status}</b>\n"
            f"Ref: <code>{order.order_ref}</code>\n\n"
            f"Kalau sudah bayar tapi belum tercatat, tunggu beberapa menit "
            f"lalu klik cek ulang.",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_confirm(order.payment_url or ""),
        )
        return

    if action == "cancel":
        await q.edit_message_text(
            "Batalkan transaksi belum diimplementasi di M1.",
            reply_markup=back_only(),
        )
        return


def register(app) -> None:
    app.add_handler(CallbackQueryHandler(pay_router, pattern=r"^pay:"))

"""ZIVPN account CRUD flows via Telegram."""
from __future__ import annotations

import logging

from sqlalchemy import select
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.constants import ParseMode
from telegram.ext import (
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    ConversationHandler,
    MessageHandler,
    filters,
)

from ..balance import InsufficientBalance, deduct, refund
from ..config import settings
from ..db import get_session
from ..keyboards import back_only
from ..models import VPS, Protocol
from ..services import zivpn_accounts as svc
from .account_common import no_vps_error, pick_vps
from .start import get_or_create_user

log = logging.getLogger(__name__)

# States (offset so they don't clash with ssh_account.py)
Z_USERNAME, Z_DURATION = range(400, 402)
Z_DELETE_USER, = range(500, 501)


async def create_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.ZIVPN)
    if not vps:
        await no_vps_error(q, "ZIVPN")
        return ConversationHandler.END
    context.user_data["vps_id"] = vps.id
    await q.edit_message_text(
        f"<b>➕ Buat ZIVPN Account</b>\n"
        f"VPS: <code>{vps.label}</code> ({vps.host})\n\n"
        f"Kirim <b>label</b> untuk akun ini (3-31 karakter, huruf kecil/angka):\n\n"
        f"/cancel untuk batal.",
        parse_mode=ParseMode.HTML,
    )
    return Z_USERNAME


async def create_username(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    username = (update.message.text or "").strip().lower()
    try:
        svc.validate_username(username)
    except svc.ZIVPNError as e:
        await update.message.reply_text(f"❌ {e}\nCoba lagi:")
        return Z_USERNAME
    context.user_data["username"] = username
    price = settings.default_price_zivpn
    await update.message.reply_text(
        f"Label: <code>{username}</code>\n\n"
        f"Kirim <b>durasi (hari)</b>. Contoh: <code>30</code>\n\n"
        f"Harga: Rp {price:,} per 30 hari (proporsional).",
        parse_mode=ParseMode.HTML,
    )
    return Z_DURATION


async def create_duration(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    try:
        days = int((update.message.text or "").strip())
        if not (1 <= days <= 365):
            raise ValueError
    except ValueError:
        await update.message.reply_text("Durasi harus angka 1-365. Coba lagi:")
        return Z_DURATION

    username = context.user_data["username"]
    price = max(500, round(settings.default_price_zivpn * days / 30))
    kb = InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ Buat & Bayar", callback_data=f"zivpn:confirm:{days}"),
        InlineKeyboardButton("❌ Batal", callback_data="zivpn:cancel"),
    ]])
    await update.message.reply_text(
        f"<b>Konfirmasi:</b>\n\n"
        f"Label   : <code>{username}</code>\n"
        f"Durasi  : {days} hari\n"
        f"Harga   : <b>Rp {price:,}</b>\n",
        parse_mode=ParseMode.HTML,
        reply_markup=kb,
    )
    context.user_data["days"] = days
    context.user_data["price"] = price
    return ConversationHandler.END


async def create_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    action = (q.data or "").split(":")[1]

    if action == "cancel":
        context.user_data.clear()
        await q.edit_message_text("Batal.", reply_markup=back_only())
        return

    username = context.user_data.get("username")
    days = context.user_data.get("days")
    price = context.user_data.get("price")
    vps_id = context.user_data.get("vps_id")
    if not (username and days and price and vps_id):
        await q.edit_message_text("Session expired. Ulangi.", reply_markup=back_only())
        return

    user = await get_or_create_user(update)
    await q.edit_message_text("⏳ Add password ke config ZIVPN + restart service…")

    async with get_session() as session:
        vps_result = await session.execute(select(VPS).where(VPS.id == vps_id))
        vps = vps_result.scalar_one_or_none()
    if not vps:
        await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
        return

    async with get_session() as session:
        try:
            await deduct(session, user.id, price, memo=f"ZIVPN {username} {days}d")
        except InsufficientBalance as e:
            await q.edit_message_text(
                f"❌ {e}\n\nTop up saldo dulu.",
                reply_markup=back_only(),
            )
            return

    try:
        result = await svc.create_account(vps, username, days)
    except svc.ZIVPNError as e:
        async with get_session() as session:
            await refund(session, user.id, price, memo=f"refund ZIVPN {username}")
        await q.edit_message_text(
            f"❌ Gagal:\n<code>{e}</code>\n\nSaldo dikembalikan.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return

    await q.edit_message_text(
        f"✅ <b>ZIVPN Account Ready!</b>\n\n<pre>{svc.format_config(result)}</pre>",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )
    context.user_data.clear()


async def list_accounts(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.ZIVPN)
    if not vps:
        await no_vps_error(q, "ZIVPN")
        return
    accs = await svc.list_accounts(vps)
    if not accs:
        await q.edit_message_text(
            f"📭 Belum ada akun ZIVPN di <code>{vps.label}</code>.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return
    lines = [f"<b>📋 ZIVPN Accounts @ {vps.label}</b>\n"]
    for a in accs[:30]:
        exp = a.expires_at.strftime("%d %b") if a.expires_at else "-"
        lines.append(f"🟢 <code>{a.username}</code> exp {exp}")
    if len(accs) > 30:
        lines.append(f"\n<i>… dan {len(accs) - 30} lagi</i>")
    await q.edit_message_text(
        "\n".join(lines), parse_mode=ParseMode.HTML, reply_markup=back_only()
    )


async def delete_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.ZIVPN)
    if not vps:
        await no_vps_error(q, "ZIVPN")
        return ConversationHandler.END
    context.user_data["vps_id"] = vps.id
    await q.edit_message_text(
        "<b>🗑 Hapus ZIVPN Account</b>\n\nKetik label yang mau dihapus:",
        parse_mode=ParseMode.HTML,
    )
    return Z_DELETE_USER


async def delete_do(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    username = (update.message.text or "").strip().lower()
    vps_id = context.user_data.get("vps_id")
    if not vps_id:
        return ConversationHandler.END
    async with get_session() as session:
        result = await session.execute(select(VPS).where(VPS.id == vps_id))
        vps = result.scalar_one_or_none()
    if not vps:
        await update.message.reply_text("VPS hilang.")
        return ConversationHandler.END

    try:
        await svc.delete_account(vps, username)
    except svc.ZIVPNError as e:
        await update.message.reply_text(f"❌ {e}")
        return ConversationHandler.END

    await update.message.reply_text(
        f"✅ <code>{username}</code> dihapus.",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )
    context.user_data.clear()
    return ConversationHandler.END


async def restart_service(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.ZIVPN)
    if not vps:
        await no_vps_error(q, "ZIVPN")
        return
    try:
        await svc.restart_service(vps)
        await q.edit_message_text(
            "🔄 Service ZIVPN di-restart.", reply_markup=back_only()
        )
    except Exception as e:  # noqa: BLE001
        await q.edit_message_text(
            f"❌ Gagal restart: <code>{e}</code>",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data.clear()
    if update.message:
        await update.message.reply_text("Batal.")
    return ConversationHandler.END


def register(app) -> None:
    create_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(create_start, pattern=r"^zivpn:create$")],
        states={
            Z_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, create_username)],
            Z_DURATION: [MessageHandler(filters.TEXT & ~filters.COMMAND, create_duration)],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", cancel)],
        allow_reentry=True,
    )
    app.add_handler(create_conv)
    app.add_handler(CallbackQueryHandler(create_confirm, pattern=r"^zivpn:(confirm|cancel)"))

    delete_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(delete_start, pattern=r"^zivpn:delete$")],
        states={
            Z_DELETE_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, delete_do)],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", cancel)],
        allow_reentry=True,
    )
    app.add_handler(delete_conv)

    app.add_handler(CallbackQueryHandler(list_accounts, pattern=r"^zivpn:list$"))
    app.add_handler(CallbackQueryHandler(restart_service, pattern=r"^zivpn:restart$"))

"""SSH account CRUD flows via Telegram."""
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

from ..balance import InsufficientBalance, deduct
from ..config import settings
from ..db import get_session
from ..keyboards import back_only
from ..models import Account, Protocol
from ..services import ssh_accounts as svc
from .account_common import no_vps_error, pick_vps
from .start import get_or_create_user

log = logging.getLogger(__name__)

# States
S_USERNAME, S_DURATION = range(100, 102)
S_DELETE_USER, = range(200, 201)
S_RENEW_USER, S_RENEW_DAYS = range(300, 302)


# ── CREATE ──────────────────────────────────────────────────────────
async def create_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.SSH)
    if not vps:
        await no_vps_error(q, "SSH")
        return ConversationHandler.END
    context.user_data["vps_id"] = vps.id
    await q.edit_message_text(
        f"<b>➕ Buat SSH Account</b>\n"
        f"VPS: <code>{vps.label}</code> ({vps.host})\n\n"
        f"Kirim <b>username</b> (3-16 huruf/angka, huruf kecil):\n\n"
        f"Ketik /cancel untuk batal.",
        parse_mode=ParseMode.HTML,
    )
    return S_USERNAME


async def create_username(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    username = (update.message.text or "").strip().lower()
    try:
        svc.validate_username(username)
    except svc.SSHAccountError as e:
        await update.message.reply_text(f"❌ {e}\nCoba lagi:")
        return S_USERNAME
    context.user_data["username"] = username
    price_per_30 = settings.default_price_ssh
    await update.message.reply_text(
        f"Username: <code>{username}</code>\n\n"
        f"Kirim <b>durasi (hari)</b>. Contoh: <code>30</code>\n\n"
        f"Harga: Rp {price_per_30:,} per 30 hari (proporsional untuk durasi lain).",
        parse_mode=ParseMode.HTML,
    )
    return S_DURATION


async def create_duration(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    try:
        days = int((update.message.text or "").strip())
        if not (1 <= days <= 365):
            raise ValueError
    except ValueError:
        await update.message.reply_text("Durasi harus angka 1-365. Coba lagi:")
        return S_DURATION

    username = context.user_data["username"]
    vps_id = context.user_data["vps_id"]
    price = max(500, round(settings.default_price_ssh * days / 30))

    # Confirm
    kb = InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ Buat & Bayar", callback_data=f"ssh:confirm:{days}"),
        InlineKeyboardButton("❌ Batal", callback_data="ssh:cancel"),
    ]])
    await update.message.reply_text(
        f"<b>Konfirmasi:</b>\n\n"
        f"Username: <code>{username}</code>\n"
        f"Durasi  : {days} hari\n"
        f"Harga   : <b>Rp {price:,}</b>\n",
        parse_mode=ParseMode.HTML,
        reply_markup=kb,
    )
    context.user_data["days"] = days
    context.user_data["price"] = price
    context.user_data["vps_id"] = vps_id
    return ConversationHandler.END


async def create_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    action = (q.data or "").split(":")[1]

    if action == "cancel":
        context.user_data.pop("username", None)
        context.user_data.pop("days", None)
        context.user_data.pop("price", None)
        context.user_data.pop("vps_id", None)
        await q.edit_message_text("Batal.", reply_markup=back_only())
        return

    # confirm
    username = context.user_data.get("username")
    days = context.user_data.get("days")
    price = context.user_data.get("price")
    vps_id = context.user_data.get("vps_id")
    if not (username and days and price and vps_id):
        await q.edit_message_text("Session expired. Ulangi dari menu.", reply_markup=back_only())
        return

    user = await get_or_create_user(update)
    await q.edit_message_text("⏳ Sedang buat akun di VPS…")

    # Look up VPS
    from ..models import VPS
    async with get_session() as session:
        vps_result = await session.execute(select(VPS).where(VPS.id == vps_id))
        vps = vps_result.scalar_one_or_none()
        if not vps:
            await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
            return

    # 1) Deduct balance FIRST (fail-fast if insufficient)
    async with get_session() as session:
        try:
            await deduct(session, user.id, price, memo=f"SSH {username} {days}d")
        except InsufficientBalance as e:
            await q.edit_message_text(
                f"❌ {e}\n\nTop up saldo dulu di menu 💰 Top Up Saldo.",
                reply_markup=back_only(),
            )
            return

    # 2) Create account remotely
    try:
        result = await svc.create_account(
            vps=vps, username=username, duration_days=days,
        )
    except svc.SSHAccountError as e:
        # Refund on failure
        from ..balance import refund
        async with get_session() as session:
            await refund(session, user.id, price, memo=f"refund SSH {username}")
        await q.edit_message_text(
            f"❌ Gagal buat akun:\n<code>{e}</code>\n\nSaldo dikembalikan.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return

    config_text = svc.format_config(result)
    await q.edit_message_text(
        f"✅ <b>SSH Account Ready!</b>\n\n<pre>{config_text}</pre>",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )


# ── LIST ────────────────────────────────────────────────────────────
async def list_accounts(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.SSH)
    if not vps:
        await no_vps_error(q, "SSH")
        return
    accs = await svc.list_accounts(vps)
    if not accs:
        await q.edit_message_text(
            f"📭 Belum ada akun SSH di <code>{vps.label}</code>.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return
    lines = [f"<b>📋 SSH Accounts @ {vps.label}</b>\n"]
    for a in accs[:30]:
        emoji = "🟢" if a.is_active else "⚫"
        exp = a.expires_at.strftime("%d %b") if a.expires_at else "-"
        lines.append(f"{emoji} <code>{a.username}</code> exp {exp}")
    if len(accs) > 30:
        lines.append(f"\n<i>… dan {len(accs) - 30} lagi</i>")
    await q.edit_message_text(
        "\n".join(lines), parse_mode=ParseMode.HTML, reply_markup=back_only()
    )


# ── DELETE ──────────────────────────────────────────────────────────
async def delete_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.SSH)
    if not vps:
        await no_vps_error(q, "SSH")
        return ConversationHandler.END
    context.user_data["vps_id"] = vps.id
    await q.edit_message_text(
        "<b>🗑 Hapus SSH Account</b>\n\nKetik username yang mau dihapus:",
        parse_mode=ParseMode.HTML,
    )
    return S_DELETE_USER


async def delete_do(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    username = (update.message.text or "").strip().lower()
    vps_id = context.user_data.get("vps_id")
    if not vps_id:
        await update.message.reply_text("Session hilang. Ulangi.")
        return ConversationHandler.END

    from ..models import VPS
    async with get_session() as session:
        result = await session.execute(select(VPS).where(VPS.id == vps_id))
        vps = result.scalar_one_or_none()
    if not vps:
        await update.message.reply_text("VPS tidak ditemukan.")
        return ConversationHandler.END

    try:
        await svc.delete_account(vps, username)
    except svc.SSHAccountError as e:
        await update.message.reply_text(f"❌ {e}")
        return ConversationHandler.END

    await update.message.reply_text(
        f"✅ Akun <code>{username}</code> dihapus.",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )
    context.user_data.pop("vps_id", None)
    return ConversationHandler.END


# ── RENEW ───────────────────────────────────────────────────────────
async def renew_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    vps = await pick_vps(update, Protocol.SSH)
    if not vps:
        await no_vps_error(q, "SSH")
        return ConversationHandler.END
    context.user_data["vps_id"] = vps.id
    await q.edit_message_text(
        "<b>♻️ Renew SSH Account</b>\n\nKetik username yang mau di-renew:",
        parse_mode=ParseMode.HTML,
    )
    return S_RENEW_USER


async def renew_user(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    username = (update.message.text or "").strip().lower()
    context.user_data["username"] = username
    await update.message.reply_text(f"Perpanjang berapa hari? Contoh: <code>30</code>",
                                     parse_mode=ParseMode.HTML)
    return S_RENEW_DAYS


async def renew_days(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    try:
        days = int((update.message.text or "").strip())
        if not (1 <= days <= 365):
            raise ValueError
    except ValueError:
        await update.message.reply_text("Durasi harus 1-365. Coba lagi:")
        return S_RENEW_DAYS

    username = context.user_data["username"]
    vps_id = context.user_data["vps_id"]
    price = max(500, round(settings.default_price_ssh * days / 30))

    user = await get_or_create_user(update)
    async with get_session() as session:
        try:
            await deduct(session, user.id, price, memo=f"renew SSH {username} {days}d")
        except InsufficientBalance as e:
            await update.message.reply_text(f"❌ {e}")
            return ConversationHandler.END

    from ..models import VPS
    async with get_session() as session:
        result = await session.execute(select(VPS).where(VPS.id == vps_id))
        vps = result.scalar_one_or_none()
    if not vps:
        await update.message.reply_text("VPS hilang.")
        return ConversationHandler.END

    try:
        new_exp = await svc.renew_account(vps, username, days)
    except svc.SSHAccountError as e:
        from ..balance import refund
        async with get_session() as session:
            await refund(session, user.id, price, memo=f"refund renew {username}")
        await update.message.reply_text(f"❌ {e}\n\nSaldo dikembalikan.")
        return ConversationHandler.END

    await update.message.reply_text(
        f"✅ Renewed! <code>{username}</code> baru berlaku sampai "
        f"<b>{new_exp:%d %b %Y}</b>",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )
    context.user_data.clear()
    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data.clear()
    if update.message:
        await update.message.reply_text("Batal.")
    return ConversationHandler.END


def register(app) -> None:
    # Create wizard
    create_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(create_start, pattern=r"^ssh:create$")],
        states={
            S_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, create_username)],
            S_DURATION: [MessageHandler(filters.TEXT & ~filters.COMMAND, create_duration)],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", cancel)],
        allow_reentry=True,
    )
    app.add_handler(create_conv)
    app.add_handler(CallbackQueryHandler(create_confirm, pattern=r"^ssh:(confirm|cancel)"))

    # Delete wizard
    delete_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(delete_start, pattern=r"^ssh:delete$")],
        states={
            S_DELETE_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, delete_do)],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", cancel)],
        allow_reentry=True,
    )
    app.add_handler(delete_conv)

    # Renew wizard
    renew_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(renew_start, pattern=r"^ssh:renew$")],
        states={
            S_RENEW_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, renew_user)],
            S_RENEW_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, renew_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", cancel)],
        allow_reentry=True,
    )
    app.add_handler(renew_conv)

    # List (no conv needed)
    app.add_handler(CallbackQueryHandler(list_accounts, pattern=r"^ssh:list$"))

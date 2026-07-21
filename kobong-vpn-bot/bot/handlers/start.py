"""/start command and root callback router."""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlalchemy import select
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import CallbackQueryHandler, CommandHandler, ContextTypes

from ..banner import welcome_text
from ..config import settings
from ..db import get_session
from ..keyboards import (
    back_only,
    main_menu,
    payment_amount_menu,
    protocol_menu,
    vps_menu,
    zivpn_menu,
)
from ..models import User, UserRole, VPS

log = logging.getLogger(__name__)


async def get_or_create_user(update: Update) -> User:
    """Fetch existing user or create a new one on first contact."""
    tg_user = update.effective_user
    if tg_user is None:
        raise RuntimeError("update has no effective_user")

    async with get_session() as session:
        result = await session.execute(
            select(User).where(User.telegram_id == tg_user.id)
        )
        user = result.scalar_one_or_none()
        if user is None:
            role = (
                UserRole.SUPER_ADMIN
                if tg_user.id in settings.admin_ids
                else UserRole.RESELLER
            )
            user = User(
                telegram_id=tg_user.id,
                username=tg_user.username,
                first_name=tg_user.first_name,
                role=role,
            )
            session.add(user)
            log.info("New user registered: tg=%s role=%s", tg_user.id, role.value)
        else:
            user.last_active_at = datetime.now(timezone.utc)
        return user


async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = await get_or_create_user(update)
    if user.role == UserRole.BANNED:
        await update.message.reply_text("⛔ Akun kamu diblokir.")
        return

    is_admin = user.role == UserRole.SUPER_ADMIN

    # Find current VPS label if any
    async with get_session() as session:
        result = await session.execute(
            select(VPS).where(VPS.owner_id == user.id).limit(1)
        )
        vps = result.scalar_one_or_none()
        current_vps = vps.label if vps else None

    text = welcome_text(
        user_name=user.first_name or user.username or "Sobat",
        is_admin=is_admin,
        balance=user.balance,
    )
    await update.message.reply_text(
        text,
        parse_mode=ParseMode.HTML,
        reply_markup=main_menu(is_admin=is_admin, current_vps=current_vps),
    )


async def menu_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Route `menu:*` callback queries to the right submenu."""
    q = update.callback_query
    await q.answer()
    data = q.data or ""
    _, section = data.split(":", 1)

    user = await get_or_create_user(update)
    is_admin = user.role == UserRole.SUPER_ADMIN

    if section == "main":
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.owner_id == user.id).limit(1)
            )
            vps = result.scalar_one_or_none()
            current_vps = vps.label if vps else None

        await q.edit_message_text(
            welcome_text(
                user_name=user.first_name or user.username or "Sobat",
                is_admin=is_admin,
                balance=user.balance,
            ),
            parse_mode=ParseMode.HTML,
            reply_markup=main_menu(is_admin=is_admin, current_vps=current_vps),
        )
        return

    # Protocol submenus
    protocol_map = {
        "ssh": "SSH", "vmess": "VMess", "vless": "VLESS",
        "trojan": "Trojan", "shadow": "Shadowsocks",
        "openvpn": "OpenVPN", "slowdns": "SlowDNS",
    }
    if section in protocol_map:
        await q.edit_message_text(
            f"<b>{protocol_map[section]} Menu</b>\n\nPilih aksi di bawah:",
            parse_mode=ParseMode.HTML,
            reply_markup=protocol_menu(section),
        )
        return

    if section == "zivpn":
        await q.edit_message_text(
            "<b>🚀 ZIVPN Menu</b>\n\n"
            "ZIVPN adalah UDP tunnel protocol dari <i>zivpn.com</i>. "
            "Cocok untuk koneksi seluler / paket unlimited game.\n\n"
            "Pilih aksi di bawah:",
            parse_mode=ParseMode.HTML,
            reply_markup=zivpn_menu(),
        )
        return

    if section == "payment":
        if not settings.is_pakasir_enabled:
            await q.edit_message_text(
                "⚠️ Payment gateway belum dikonfigurasi.\n\n"
                "Admin bot perlu setup <code>PAKASIR_SLUG</code> dan "
                "<code>PAKASIR_API_KEY</code> di .env terlebih dahulu.",
                parse_mode=ParseMode.HTML,
                reply_markup=back_only(),
            )
            return
        await q.edit_message_text(
            f"<b>💰 Top Up Saldo</b>\n\n"
            f"Saldo saat ini: <b>Rp {user.balance:,}</b>\n\n"
            f"Pilih nominal top-up:",
            parse_mode=ParseMode.HTML,
            reply_markup=payment_amount_menu(),
        )
        return

    if section == "profile":
        text = (
            f"<b>👤 Profil</b>\n\n"
            f"ID Telegram: <code>{user.telegram_id}</code>\n"
            f"Username: @{user.username or '(none)'}\n"
            f"Role: <b>{user.role.value}</b>\n"
            f"Saldo: <b>Rp {user.balance:,}</b>\n"
            f"Terdaftar: {user.created_at:%d %b %Y}\n"
        )
        await q.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=back_only())
        return

    if section == "help":
        await q.edit_message_text(
            "<b>❓ Bantuan</b>\n\n"
            "• Tambahkan VPS kamu lewat menu <b>🖥 VPS</b>\n"
            "• Install stack tunneling (Xray/SSH/ZIVPN/dll)\n"
            "• Buat akun untuk client kamu lewat menu protokol\n"
            "• Top up saldo lewat menu <b>💰 Top Up Saldo</b>\n"
            "• Setiap create akun akan memotong saldo sesuai harga produk\n\n"
            "Butuh bantuan lebih lanjut? Hubungi admin bot.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return

    # Fallback for stubs
    await q.edit_message_text(
        f"<b>{section.upper()}</b>\n\n"
        f"🚧 Fitur ini akan tersedia di milestone berikutnya.\n\n"
        f"<i>Sedang dalam pengembangan.</i>",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )


def register(app) -> None:
    app.add_handler(CommandHandler("start", start_cmd))
    app.add_handler(CommandHandler("menu", start_cmd))
    app.add_handler(CallbackQueryHandler(menu_router, pattern=r"^menu:"))

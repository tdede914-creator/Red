"""VPS registration & management handlers (skeleton for M1).

Full wizard for adding VPS (asking IP → user → pass → verify SSH) is a
conversation flow that will be implemented in M2. For now this exposes the
list/select flow so the main menu is navigable end-to-end.
"""
from __future__ import annotations

import logging

from sqlalchemy import select
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import CallbackQueryHandler, ContextTypes

from ..db import get_session
from ..keyboards import back_only, vps_list, vps_menu
from ..models import VPS
from .start import get_or_create_user

log = logging.getLogger(__name__)


async def vps_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    data = (q.data or "").split(":")
    if len(data) < 2:
        return
    action = data[1]

    user = await get_or_create_user(update)

    if action == "main":
        async with get_session() as session:
            result = await session.execute(select(VPS).where(VPS.owner_id == user.id))
            has_vps = result.first() is not None
        await q.edit_message_text(
            "<b>🖥 Kelola VPS</b>\n\n"
            "Daftarkan VPS kamu lalu install stack tunneling langsung dari bot.",
            parse_mode=ParseMode.HTML,
            reply_markup=vps_menu(has_vps=has_vps),
        )
        return

    if action == "list":
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.owner_id == user.id).order_by(VPS.created_at)
            )
            vps_items = [
                (v.id, v.label, v.host, v.status.value) for v in result.scalars()
            ]
        if not vps_items:
            await q.edit_message_text(
                "📭 Belum ada VPS terdaftar.",
                reply_markup=vps_menu(has_vps=False),
            )
            return
        await q.edit_message_text(
            f"<b>📋 List VPS ({len(vps_items)})</b>\n\nPilih VPS untuk detail:",
            parse_mode=ParseMode.HTML,
            reply_markup=vps_list(vps_items),
        )
        return

    if action == "add":
        await q.edit_message_text(
            "<b>➕ Tambah VPS Baru</b>\n\n"
            "🚧 Wizard tambah VPS akan tersedia di Milestone 2.\n\n"
            "<i>Rencana flow:</i>\n"
            "1. Kirim IP / hostname\n"
            "2. Kirim SSH user (default: root)\n"
            "3. Kirim password atau upload private key\n"
            "4. Bot verifikasi koneksi SSH\n"
            "5. Pilih stack yang mau di-install\n"
            "6. Bot jalankan installer dengan live progress",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return

    # Fallback stub for other actions
    await q.edit_message_text(
        f"<b>VPS: {action}</b>\n\n🚧 Coming in M2.",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )


def register(app) -> None:
    app.add_handler(CallbackQueryHandler(vps_router, pattern=r"^vps:"))

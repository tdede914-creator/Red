"""Shared helpers for account CRUD handlers (SSH, ZIVPN, and future protocols)."""
from __future__ import annotations

import logging
from typing import Optional

from sqlalchemy import select
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

from ..db import get_session
from ..models import VPS, Protocol, VPSStatus

log = logging.getLogger(__name__)


async def pick_vps(update: Update, protocol: Protocol) -> Optional[VPS]:
    """Pick the user's first ACTIVE VPS that has this protocol installed.

    Returns None if no suitable VPS. (Future: prompt user to pick when they
    have multiple VPS.)
    """
    from .start import get_or_create_user

    user = await get_or_create_user(update)
    async with get_session() as session:
        result = await session.execute(
            select(VPS)
            .where(VPS.owner_id == user.id, VPS.status == VPSStatus.ACTIVE)
            .order_by(VPS.installed_at.desc())
        )
        for vps in result.scalars():
            if vps.has_protocol(protocol):
                return vps
    return None


async def no_vps_error(q, protocol_label: str):
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Tambah VPS", callback_data="vps:add")],
        [InlineKeyboardButton("🔙 Menu Utama", callback_data="menu:main")],
    ])
    await q.edit_message_text(
        f"⚠️ Belum ada VPS aktif dengan <b>{protocol_label}</b> ter-install.\n\n"
        f"Daftarkan VPS dulu + install stack-nya (menu 🖥 VPS).",
        parse_mode="HTML",
        reply_markup=kb,
    )

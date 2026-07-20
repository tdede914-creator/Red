"""Fallback stub for protocols that don't have full CRUD implementations yet.

Registered LAST so specific handlers (ssh:*, zivpn:*) take precedence.
"""
from __future__ import annotations

from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import CallbackQueryHandler, ContextTypes

from ..keyboards import back_only

_PROTO_LABELS = {
    "vmess": "📦 VMess",
    "vless": "⚡ VLESS",
    "trojan": "🛡 Trojan",
    "shadow": "👥 Shadowsocks",
    "openvpn": "🔓 OpenVPN",
    "slowdns": "🌐 SlowDNS",
}

_ACTION_LABELS = {
    "create": "Buat Akun",
    "renew": "Perpanjang Akun",
    "delete": "Hapus Akun",
    "list": "List Akun",
    "lock": "Lock / Unlock",
    "check": "Cek Login",
    "trial": "Trial Akun",
    "status": "Status Service",
    "config": "Ganti Config",
}


async def protocol_stub(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    parts = (q.data or "").split(":")
    proto = parts[0]
    action = parts[1] if len(parts) > 1 else "?"

    proto_label = _PROTO_LABELS.get(proto, proto.upper())
    action_label = _ACTION_LABELS.get(action, action)

    await q.edit_message_text(
        f"<b>{proto_label} → {action_label}</b>\n\n"
        f"🚧 Untuk {proto_label} CRUD lengkap saya butuh manipulasi Xray "
        f"config.json JSON — akan ditambahkan setelah kamu test SSH & ZIVPN "
        f"berjalan mulus.\n\n"
        f"<i>Sudah tersedia sekarang:</i>\n"
        f"• 🔐 SSH (create/list/delete/renew)\n"
        f"• 🚀 ZIVPN (create/list/delete/restart)",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )


def register(app) -> None:
    # Only match protocols WITHOUT full impl. Do NOT include ssh|zivpn here.
    pattern = r"^(vmess|vless|trojan|shadow|openvpn|slowdns):"
    app.add_handler(CallbackQueryHandler(protocol_stub, pattern=pattern))

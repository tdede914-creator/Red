"""Generic stub handler for protocol callbacks (M1 placeholder).

Real per-protocol logic (create/renew/delete/list/lock/check) will be added
in M3-M5. For now this responds gracefully so navigation doesn't dead-end.
"""
from __future__ import annotations

from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import CallbackQueryHandler, ContextTypes

from ..keyboards import back_only

_PROTO_LABELS = {
    "ssh": "🔐 SSH",
    "vmess": "📦 VMess",
    "vless": "⚡ VLESS",
    "trojan": "🛡 Trojan",
    "shadow": "👥 Shadowsocks",
    "zivpn": "🚀 ZIVPN",
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
    "restart": "Restart Service",
    "config": "Ganti Port / Password",
    "status": "Status Service",
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
        f"🚧 Fitur ini akan aktif setelah kamu:\n"
        f"1. Daftarkan VPS (Milestone 2)\n"
        f"2. Install {proto_label.split()[-1]} stack di VPS tersebut\n\n"
        f"Milestone saat ini: <b>M1 — Scaffold & Fondasi</b>",
        parse_mode=ParseMode.HTML,
        reply_markup=back_only(),
    )


def register(app) -> None:
    pattern = r"^(ssh|vmess|vless|trojan|shadow|zivpn|openvpn|slowdns):"
    app.add_handler(CallbackQueryHandler(protocol_stub, pattern=pattern))

"""KOBONG VPN BOT — ASCII banner and branding strings."""
from __future__ import annotations

BRAND_NAME = "KOBONG VPN BOT"
BRAND_TAGLINE = "Multi-Protocol VPN Manager • Telegram Edition"
BRAND_VERSION = "0.1.0"

# ASCII banner (5-line, monospace-safe)
BANNER = r"""
╔═══════════════════════════════════════════════════════════╗
║   ██╗  ██╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗ ██████╗    ║
║   ██║ ██╔╝██╔═══██╗██╔══██╗██╔═══██╗████╗  ██║██╔════╝    ║
║   █████╔╝ ██║   ██║██████╔╝██║   ██║██╔██╗ ██║██║  ███╗   ║
║   ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║   ║
║   ██║  ██╗╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝   ║
║   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝    ║
║                     V P N   B O T                         ║
╚═══════════════════════════════════════════════════════════╝
"""

# Compact banner for inline usage (fits in Telegram single message)
COMPACT_BANNER = "🌙 KOBONG VPN BOT 🌙"


def welcome_text(user_name: str, is_admin: bool = False, balance: int = 0) -> str:
    """Build the welcome / /start message."""
    role_badge = "👑 SUPER ADMIN" if is_admin else "👤 RESELLER"
    return (
        f"<pre>{BANNER.strip()}</pre>\n"
        f"<b>Selamat datang, {user_name}!</b>\n\n"
        f"┌─────────────────────────\n"
        f"│ 🏷  {BRAND_NAME}\n"
        f"│ 📌 {BRAND_TAGLINE}\n"
        f"│ 🆔 Status: {role_badge}\n"
        f"│ 💰 Saldo: Rp {balance:,}\n"
        f"│ 🔖 v{BRAND_VERSION}\n"
        f"└─────────────────────────\n\n"
        f"Bot ini bantu kamu install VPN stack lengkap ke VPS "
        f"(SSH, VMess, VLESS, Trojan, Shadowsocks, <b>ZIVPN</b>, "
        f"OpenVPN, SlowDNS) dan kelola akun langsung dari Telegram.\n\n"
        f"Pilih menu di bawah untuk mulai 👇"
    )

"""Inline keyboard builders for KOBONG VPN BOT.

Callback data convention:
    <namespace>:<action>[:<param>...]

Examples:
    menu:main            → main menu
    menu:ssh             → SSH submenu
    vps:add              → add VPS wizard
    vps:sel:<id>         → select VPS by id
    ssh:create:<vps_id>  → create SSH account on VPS
"""
from __future__ import annotations

from typing import List, Optional, Sequence

from telegram import InlineKeyboardButton, InlineKeyboardMarkup


# ── Helpers ─────────────────────────────────────────────────────────
def _btn(label: str, data: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(label, callback_data=data)


def _grid(rows: Sequence[Sequence[InlineKeyboardButton]]) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([list(r) for r in rows])


BACK_TO_MAIN = _btn("🔙 Menu Utama", "menu:main")


# ── Main menu ───────────────────────────────────────────────────────
def main_menu(is_admin: bool = False, current_vps: Optional[str] = None) -> InlineKeyboardMarkup:
    """Root menu — mirrors the 15-option VPS terminal menu."""
    vps_row = [
        _btn(
            f"🖥 VPS: {current_vps}" if current_vps else "➕ Tambah VPS",
            "vps:main",
        ),
    ]

    protocol_rows = [
        [_btn("🔐 SSH", "menu:ssh"),          _btn("📦 VMESS", "menu:vmess")],
        [_btn("⚡ VLESS", "menu:vless"),       _btn("🛡 TROJAN", "menu:trojan")],
        [_btn("👥 SHADOW", "menu:shadow"),     _btn("🚀 ZIVPN", "menu:zivpn")],
        [_btn("🔓 OPENVPN", "menu:openvpn"),  _btn("🌐 SLOWDNS", "menu:slowdns")],
    ]

    utility_rows = [
        [_btn("🆓 Trial", "menu:trial"),       _btn("♻️ Autoreboot", "menu:autoreboot")],
        [_btn("💾 Backup/Restore", "menu:backup"), _btn("📊 Stats VPS", "menu:stats")],
        [_btn("🔧 Settings", "menu:settings")],
    ]

    footer_rows = [
        [_btn("💰 Top Up Saldo", "menu:payment"), _btn("📜 Riwayat", "menu:history")],
    ]

    if is_admin:
        footer_rows.append([_btn("👑 Admin Panel", "menu:admin")])

    footer_rows.append([_btn("❓ Bantuan", "menu:help"), _btn("👤 Profil", "menu:profile")])

    return _grid([vps_row, *protocol_rows, *utility_rows, *footer_rows])


# ── Protocol submenu (generic factory) ──────────────────────────────
def protocol_menu(proto: str) -> InlineKeyboardMarkup:
    """Standard sub-menu for a protocol (ssh, vmess, vless, trojan, shadow)."""
    return _grid([
        [_btn("➕ Buat Akun", f"{proto}:create"),  _btn("♻️ Renew", f"{proto}:renew")],
        [_btn("🗑 Hapus Akun", f"{proto}:delete"), _btn("📋 List Akun", f"{proto}:list")],
        [_btn("🔒 Lock/Unlock", f"{proto}:lock"),  _btn("🔍 Cek Login", f"{proto}:check")],
        [_btn("⏰ Trial", f"{proto}:trial")],
        [BACK_TO_MAIN],
    ])


def zivpn_menu() -> InlineKeyboardMarkup:
    """ZIVPN has extra options for service management."""
    return _grid([
        [_btn("➕ Buat Akun", "zivpn:create"),  _btn("♻️ Renew", "zivpn:renew")],
        [_btn("🗑 Hapus Akun", "zivpn:delete"), _btn("📋 List Akun", "zivpn:list")],
        [_btn("🔄 Restart Service", "zivpn:restart"),
         _btn("⚙️ Ganti Port/Pass", "zivpn:config")],
        [_btn("📊 Status Service", "zivpn:status")],
        [BACK_TO_MAIN],
    ])


# ── VPS management ──────────────────────────────────────────────────
def vps_menu(has_vps: bool = False) -> InlineKeyboardMarkup:
    rows = [
        [_btn("➕ Tambah VPS Baru", "vps:add")],
    ]
    if has_vps:
        rows.append([_btn("📋 List VPS Saya", "vps:list"),
                     _btn("🔀 Ganti VPS Aktif", "vps:switch")])
        rows.append([_btn("🚀 Install Stack", "vps:install"),
                     _btn("🗑 Hapus VPS", "vps:remove")])
        rows.append([_btn("🔎 Cek Status", "vps:status")])
    rows.append([BACK_TO_MAIN])
    return _grid(rows)


def vps_install_options() -> InlineKeyboardMarkup:
    """Choose what to install on a fresh VPS."""
    return _grid([
        [_btn("📦 Full Stack (semua)", "vps:install:full")],
        [_btn("🔐 SSH + Xray only", "vps:install:xray")],
        [_btn("🚀 + ZIVPN", "vps:install:zivpn")],
        [_btn("🎯 Custom Pilihan", "vps:install:custom")],
        [BACK_TO_MAIN],
    ])


def vps_list(vps_items: List[tuple[int, str, str, str]]) -> InlineKeyboardMarkup:
    """vps_items: list of (id, label, host, status)."""
    rows = [
        [_btn(f"{status_emoji(s)} {label} ({host})", f"vps:sel:{vid}")]
        for vid, label, host, s in vps_items
    ]
    rows.append([_btn("➕ Tambah Baru", "vps:add"), BACK_TO_MAIN])
    return _grid(rows)


def status_emoji(status: str) -> str:
    return {
        "active": "🟢",
        "installing": "🟡",
        "pending": "⚪",
        "error": "🔴",
        "disabled": "⚫",
    }.get(status, "⚪")


# ── Payment ─────────────────────────────────────────────────────────
def payment_amount_menu() -> InlineKeyboardMarkup:
    return _grid([
        [_btn("Rp 10.000", "pay:amount:10000"),  _btn("Rp 25.000", "pay:amount:25000")],
        [_btn("Rp 50.000", "pay:amount:50000"),  _btn("Rp 100.000", "pay:amount:100000")],
        [_btn("Rp 250.000", "pay:amount:250000"), _btn("Rp 500.000", "pay:amount:500000")],
        [_btn("💵 Nominal Lain", "pay:amount:custom")],
        [BACK_TO_MAIN],
    ])


def payment_method_menu(amount: int) -> InlineKeyboardMarkup:
    return _grid([
        [_btn("📱 QRIS", f"pay:method:qris:{amount}")],
        [_btn("🏦 BCA/Permata VA", f"pay:method:permata_va:{amount}"),
         _btn("🏦 BNI VA", f"pay:method:bni_va:{amount}")],
        [_btn("🏦 BRI VA", f"pay:method:bri_va:{amount}"),
         _btn("🏦 CIMB VA", f"pay:method:cimb_niaga_va:{amount}")],
        [_btn("🏦 Maybank VA", f"pay:method:maybank_va:{amount}")],
        [BACK_TO_MAIN],
    ])


def payment_confirm(payment_url: str) -> InlineKeyboardMarkup:
    return _grid([
        [InlineKeyboardButton("💳 Bayar Sekarang", url=payment_url)],
        [_btn("🔍 Cek Status Pembayaran", "pay:check")],
        [_btn("❌ Batalkan", "pay:cancel")],
    ])


# ── Confirmation dialog ─────────────────────────────────────────────
def confirm(callback_yes: str, callback_no: str = "menu:main") -> InlineKeyboardMarkup:
    return _grid([
        [_btn("✅ Ya, lanjutkan", callback_yes),
         _btn("❌ Batal", callback_no)],
    ])


# ── Back-only ───────────────────────────────────────────────────────
def back_only() -> InlineKeyboardMarkup:
    return _grid([[BACK_TO_MAIN]])

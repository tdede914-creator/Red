"""VPS registration + install flow.

Uses ConversationHandler for the add-wizard, plain callbacks for
list/select/install/remove.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

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

from ..crypto import encrypt
from ..db import get_session
from ..install_orchestrator import InstallOrchestrator
from ..keyboards import back_only, vps_install_options, vps_list, vps_menu
from ..models import VPS, VPSStatus
from ..ssh_client import verify_credentials
from .start import get_or_create_user

log = logging.getLogger(__name__)

# Conversation states
ADD_LABEL, ADD_HOST, ADD_PORT, ADD_USER, ADD_CRED_TYPE, ADD_CRED = range(6)


# ── Helpers ─────────────────────────────────────────────────────────
def _vps_detail_keyboard(vps: VPS) -> InlineKeyboardMarkup:
    rows = []
    if vps.status == VPSStatus.PENDING:
        rows.append([InlineKeyboardButton("🚀 Install Stack", callback_data=f"vps:install:{vps.id}")])
    elif vps.status == VPSStatus.ACTIVE:
        rows.append([
            InlineKeyboardButton("🔎 Cek Status", callback_data=f"vps:status:{vps.id}"),
            InlineKeyboardButton("🔀 Set Aktif", callback_data=f"vps:setactive:{vps.id}"),
        ])
    elif vps.status == VPSStatus.INSTALLING:
        rows.append([InlineKeyboardButton("⏳ Instalasi berjalan…", callback_data="noop")])
    rows.append([InlineKeyboardButton("🗑 Hapus VPS", callback_data=f"vps:delete:{vps.id}")])
    rows.append([InlineKeyboardButton("🔙 Menu Utama", callback_data="menu:main")])
    return InlineKeyboardMarkup(rows)


def _vps_detail_text(vps: VPS) -> str:
    status_emoji = {
        VPSStatus.PENDING:    "⚪ Belum di-install",
        VPSStatus.INSTALLING: "⏳ Sedang install…",
        VPSStatus.ACTIVE:     "🟢 Aktif",
        VPSStatus.ERROR:      "🔴 Error",
        VPSStatus.DISABLED:   "⚫ Nonaktif",
    }
    protos = vps.installed_protocols or "(belum ada)"
    return (
        f"<b>🖥 VPS: {vps.label}</b>\n\n"
        f"Host    : <code>{vps.host}:{vps.port}</code>\n"
        f"User    : <code>{vps.ssh_user}</code>\n"
        f"Status  : {status_emoji.get(vps.status, '?')}\n"
        f"OS      : {vps.os_info or 'unknown'}\n"
        f"Domain  : <code>{vps.domain or '(auto)'}</code>\n"
        f"Protokol: {protos}\n"
    )


# ── Main VPS router (non-conversation callbacks) ────────────────────
async def vps_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    q = update.callback_query
    await q.answer()
    parts = (q.data or "").split(":")
    if len(parts) < 2:
        return
    action = parts[1]

    user = await get_or_create_user(update)

    if action == "main":
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.owner_id == user.id).limit(1)
            )
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
            items = [
                (v.id, v.label, v.host, v.status.value) for v in result.scalars()
            ]
        if not items:
            await q.edit_message_text(
                "📭 Belum ada VPS terdaftar.",
                reply_markup=vps_menu(has_vps=False),
            )
            return
        await q.edit_message_text(
            f"<b>📋 List VPS ({len(items)})</b>\n\nPilih VPS untuk detail:",
            parse_mode=ParseMode.HTML,
            reply_markup=vps_list(items),
        )
        return

    if action == "sel":
        try:
            vps_id = int(parts[2])
        except (IndexError, ValueError):
            return
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.id == vps_id, VPS.owner_id == user.id)
            )
            vps = result.scalar_one_or_none()
        if not vps:
            await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
            return
        await q.edit_message_text(
            _vps_detail_text(vps),
            parse_mode=ParseMode.HTML,
            reply_markup=_vps_detail_keyboard(vps),
        )
        return

    if action == "install":
        try:
            vps_id = int(parts[2])
        except (IndexError, ValueError):
            await q.edit_message_text(
                "<b>🚀 Install Stack</b>\n\nPilih VPS dari list dulu.",
                parse_mode=ParseMode.HTML,
                reply_markup=vps_menu(has_vps=True),
            )
            return
        await _confirm_install(update, context, vps_id)
        return

    if action == "install-confirm":
        try:
            vps_id = int(parts[2])
        except (IndexError, ValueError):
            return
        await _start_install(update, context, vps_id)
        return

    if action == "delete":
        try:
            vps_id = int(parts[2])
        except (IndexError, ValueError):
            return
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.id == vps_id, VPS.owner_id == user.id)
            )
            vps = result.scalar_one_or_none()
            if vps:
                await session.delete(vps)
        await q.edit_message_text(
            "🗑 VPS dihapus dari daftar (server target tidak diapa-apakan).",
            reply_markup=back_only(),
        )
        return

    if action == "status":
        try:
            vps_id = int(parts[2])
        except (IndexError, ValueError):
            return
        await _check_vps_status(update, context, vps_id)
        return

    if action == "setactive":
        # Currently a no-op — future: mark VPS as user's current session VPS
        await q.answer("Selected!", show_alert=False)
        return

    # Fallback
    await q.edit_message_text(
        f"Action tidak dikenal: {action}",
        reply_markup=back_only(),
    )


# ── Install trigger ─────────────────────────────────────────────────
async def _confirm_install(
    update: Update, context: ContextTypes.DEFAULT_TYPE, vps_id: int
) -> None:
    """Show install confirmation with price (skip confirmation for super admin)."""
    from ..config import settings
    from ..models import UserRole

    q = update.callback_query
    user = await get_or_create_user(update)

    async with get_session() as session:
        result = await session.execute(
            select(VPS).where(VPS.id == vps_id, VPS.owner_id == user.id)
        )
        vps = result.scalar_one_or_none()

    if not vps:
        await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
        return

    if vps.status == VPSStatus.INSTALLING:
        await q.edit_message_text("⏳ Instalasi sudah berjalan.", reply_markup=back_only())
        return

    is_super = user.role == UserRole.SUPER_ADMIN

    # Super admin: skip confirmation, install directly
    if is_super:
        await _start_install(update, context, vps_id)
        return

    # Reseller: show install fee confirmation
    fee = settings.default_price_install

    # Zero fee? Just install
    if fee == 0:
        await _start_install(update, context, vps_id)
        return

    # Insufficient balance? Show error
    if user.balance < fee:
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 Top Up Sekarang", callback_data="menu:payment")],
            [InlineKeyboardButton("🔙 Menu Utama", callback_data="menu:main")],
        ])
        await q.edit_message_text(
            f"<b>❌ Saldo Tidak Cukup</b>\n\n"
            f"Biaya jasa install: <b>Rp {fee:,}</b>\n"
            f"Saldo kamu       : Rp {user.balance:,}\n"
            f"Kurang           : <b>Rp {fee - user.balance:,}</b>\n\n"
            f"Top up dulu ya.",
            parse_mode=ParseMode.HTML,
            reply_markup=kb,
        )
        return

    # OK, confirm
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton(
            f"✅ Bayar Rp {fee:,} & Install",
            callback_data=f"vps:install-confirm:{vps_id}",
        )],
        [InlineKeyboardButton("❌ Batal", callback_data="menu:main")],
    ])
    await q.edit_message_text(
        f"<b>🚀 Konfirmasi Install</b>\n\n"
        f"VPS      : <code>{vps.label}</code> ({vps.host})\n"
        f"Biaya    : <b>Rp {fee:,}</b> (jasa install, bayar 1× per VPS)\n"
        f"Saldo    : Rp {user.balance:,}\n"
        f"Setelah  : <b>Rp {user.balance - fee:,}</b>\n\n"
        f"💡 <b>Setelah install selesai</b>, kamu bisa create akun "
        f"SSH/VMess/VLESS/Trojan/Shadowsocks/ZIVPN di VPS ini "
        f"<b>UNLIMITED &amp; GRATIS</b>.\n\n"
        f"Kalau install gagal, saldo akan otomatis dikembalikan.",
        parse_mode=ParseMode.HTML,
        reply_markup=kb,
    )


async def _start_install(update: Update, context: ContextTypes.DEFAULT_TYPE, vps_id: int) -> None:
    """Actually run the install. Charges fee before triggering (except super admin).
    Refunds on failure.
    """
    from ..balance import InsufficientBalance, deduct, refund
    from ..config import settings
    from ..models import UserRole

    q = update.callback_query
    user = await get_or_create_user(update)

    async with get_session() as session:
        result = await session.execute(
            select(VPS).where(VPS.id == vps_id, VPS.owner_id == user.id)
        )
        vps = result.scalar_one_or_none()

    if not vps:
        await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
        return

    if vps.status == VPSStatus.INSTALLING:
        await q.edit_message_text("⏳ Instalasi sudah berjalan.", reply_markup=back_only())
        return

    is_super = user.role == UserRole.SUPER_ADMIN
    fee = 0 if is_super else settings.default_price_install
    user_id = user.id
    tg_id = user.telegram_id

    # Deduct upfront (for resellers) so double-clicks don't double-charge
    if fee > 0:
        try:
            async with get_session() as session:
                await deduct(session, user_id, fee, memo=f"install {vps.label}")
        except InsufficientBalance as e:
            await q.edit_message_text(
                f"❌ {e}", reply_markup=back_only()
            )
            return

    async def edit_msg(text: str) -> None:
        try:
            await q.edit_message_text(text, parse_mode=ParseMode.HTML)
        except Exception as e:  # noqa: BLE001
            log.debug("edit_msg noop: %s", e)

    async def run_install() -> None:
        orch = InstallOrchestrator(
            vps=vps, install_mode="full", install_zivpn=True,
        )
        try:
            ok, msg = await orch.run(edit_msg)
            log.info("Install for VPS %s: ok=%s msg=%s", vps.id, ok, msg)

            # Refund on failure
            if not ok and fee > 0:
                async with get_session() as session:
                    new_bal = await refund(
                        session, user_id, fee, memo=f"refund failed install {vps.label}"
                    )
                try:
                    await context.bot.send_message(
                        chat_id=tg_id,
                        text=(
                            f"💰 <b>Saldo dikembalikan</b>\n\n"
                            f"Install gagal, biaya Rp {fee:,} sudah "
                            f"di-refund. Saldo sekarang: Rp {new_bal:,}"
                        ),
                        parse_mode=ParseMode.HTML,
                    )
                except Exception:  # noqa: BLE001
                    pass
        except Exception:  # noqa: BLE001
            log.exception("Install task crashed")
            if fee > 0:
                async with get_session() as session:
                    await refund(session, user_id, fee, memo=f"refund crashed install {vps.label}")

    asyncio.create_task(run_install())


async def _check_vps_status(update: Update, context: ContextTypes.DEFAULT_TYPE, vps_id: int) -> None:
    from ..ssh_client import KobongSSH, SSHError
    q = update.callback_query
    user = await get_or_create_user(update)

    async with get_session() as session:
        result = await session.execute(
            select(VPS).where(VPS.id == vps_id, VPS.owner_id == user.id)
        )
        vps = result.scalar_one_or_none()

    if not vps:
        await q.edit_message_text("VPS tidak ditemukan.", reply_markup=back_only())
        return

    await q.edit_message_text("🔎 Cek status services…", reply_markup=None)

    services = ["xray", "dropbear", "ssh", "kobong-zivpn"]
    try:
        async with KobongSSH(vps, timeout=15.0) as ssh:
            statuses = []
            for svc in services:
                r = await ssh.run(f"systemctl is-active {svc}", check=False, timeout=10)
                state = (r.stdout or "").strip()
                emoji = "🟢" if state == "active" else ("🔴" if state == "failed" else "⚪")
                statuses.append(f"{emoji} <code>{svc}</code>: {state}")

            uptime = await ssh.run("uptime -p", check=False, timeout=10)
            mem = await ssh.run(
                "free -m | awk 'NR==2 {print $3\"/\"$2\" MB\"}'",
                check=False, timeout=10,
            )
    except SSHError as e:
        await q.edit_message_text(
            f"❌ Gagal konek ke VPS:\n<code>{e}</code>",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        return

    text = (
        f"<b>📊 Status: {vps.label}</b>\n\n"
        + "\n".join(statuses)
        + f"\n\n<b>Uptime:</b> {(uptime.stdout or '').strip()}"
        f"\n<b>RAM:</b> {(mem.stdout or '').strip()}"
    )
    await q.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=back_only())


# ── ADD WIZARD (ConversationHandler) ────────────────────────────────
async def add_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    context.user_data.clear()
    await q.edit_message_text(
        "<b>➕ Tambah VPS Baru — 1/6</b>\n\n"
        "Kirim <b>label</b> untuk VPS ini (nama pendek, contoh: <code>SG1</code>, "
        "<code>Jakarta-A</code>). Ini cuma untuk kamu bedain di menu.\n\n"
        "Ketik /cancel untuk batal.",
        parse_mode=ParseMode.HTML,
    )
    return ADD_LABEL


async def add_label(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    label = (update.message.text or "").strip()
    if not (1 <= len(label) <= 32) or "\n" in label:
        await update.message.reply_text("Label 1-32 karakter, tanpa baris baru. Coba lagi:")
        return ADD_LABEL
    context.user_data["label"] = label
    await update.message.reply_text(
        f"<b>2/6</b>\n\nKirim <b>IP / hostname</b> VPS target.\n"
        f"Contoh: <code>157.245.100.12</code> atau <code>vps.contoh.com</code>",
        parse_mode=ParseMode.HTML,
    )
    return ADD_HOST


async def add_host(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    host = (update.message.text or "").strip()
    if not host or " " in host or len(host) > 253:
        await update.message.reply_text("Host tidak valid. Coba lagi:")
        return ADD_HOST
    context.user_data["host"] = host
    await update.message.reply_text(
        "<b>3/6</b>\n\nKirim <b>port SSH</b> (default: <code>22</code>).\n"
        "Ketik <code>22</code> atau nomor lain.",
        parse_mode=ParseMode.HTML,
    )
    return ADD_PORT


async def add_port(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    raw = (update.message.text or "").strip()
    try:
        port = int(raw)
        if not (1 <= port <= 65535):
            raise ValueError
    except ValueError:
        await update.message.reply_text("Port harus angka 1-65535. Coba lagi:")
        return ADD_PORT
    context.user_data["port"] = port
    await update.message.reply_text(
        "<b>4/6</b>\n\nKirim <b>SSH user</b> (biasanya <code>root</code>).",
        parse_mode=ParseMode.HTML,
    )
    return ADD_USER


async def add_user(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    user = (update.message.text or "").strip()
    if not user or " " in user or len(user) > 32:
        await update.message.reply_text("SSH user tidak valid. Coba lagi:")
        return ADD_USER
    context.user_data["ssh_user"] = user
    kb = InlineKeyboardMarkup([[
        InlineKeyboardButton("🔑 Password", callback_data="addvps:cred:password"),
        InlineKeyboardButton("🗝 Private Key", callback_data="addvps:cred:key"),
    ]])
    await update.message.reply_text(
        "<b>5/6</b>\n\nPakai autentikasi apa?",
        parse_mode=ParseMode.HTML,
        reply_markup=kb,
    )
    return ADD_CRED_TYPE


async def add_cred_type(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    q = update.callback_query
    await q.answer()
    kind = (q.data or "").split(":")[-1]
    context.user_data["cred_type"] = kind
    if kind == "password":
        await q.edit_message_text(
            "<b>6/6</b>\n\nKirim <b>password SSH</b> (pesan kamu akan langsung "
            "dihapus setelah diterima).",
            parse_mode=ParseMode.HTML,
        )
    else:
        await q.edit_message_text(
            "<b>6/6</b>\n\nPaste <b>private key</b> lengkap termasuk header/footer:\n\n"
            "<pre>-----BEGIN OPENSSH PRIVATE KEY-----\n"
            "...\n"
            "-----END OPENSSH PRIVATE KEY-----</pre>",
            parse_mode=ParseMode.HTML,
        )
    return ADD_CRED


async def add_cred(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    raw = update.message.text or ""
    # Delete the user's message to keep secrets out of chat history
    try:
        await update.message.delete()
    except Exception:  # noqa: BLE001
        pass

    kind = context.user_data.get("cred_type")
    label = context.user_data.get("label")
    host = context.user_data.get("host")
    port = context.user_data.get("port")
    ssh_user = context.user_data.get("ssh_user")

    if not raw.strip():
        await context.bot.send_message(update.effective_chat.id, "Kredensial kosong. Coba lagi:")
        return ADD_CRED

    msg = await context.bot.send_message(
        update.effective_chat.id,
        f"🔎 Verifikasi login SSH ke <code>{host}:{port}</code>…",
        parse_mode=ParseMode.HTML,
    )

    password: Optional[str] = None
    private_key: Optional[str] = None
    if kind == "password":
        password = raw.strip()
    else:
        private_key = raw

    ok, info = await verify_credentials(
        host=host, port=port, user=ssh_user,
        password=password, private_key=private_key,
    )
    if not ok:
        await msg.edit_text(
            f"❌ <b>Verifikasi gagal</b>\n\n{info}\n\n"
            f"Coba lagi dari awal dengan tombol <b>➕ Tambah VPS</b>.",
            parse_mode=ParseMode.HTML,
            reply_markup=back_only(),
        )
        context.user_data.clear()
        return ConversationHandler.END

    # Persist VPS
    bot_user = await get_or_create_user(update)
    async with get_session() as session:
        vps = VPS(
            owner_id=bot_user.id,
            label=label,
            host=host,
            port=port,
            ssh_user=ssh_user,
            ssh_password_enc=encrypt(password) if password else None,
            ssh_key_enc=encrypt(private_key) if private_key else None,
            os_info=info,
            status=VPSStatus.PENDING,
        )
        session.add(vps)
        await session.flush()
        vps_id = vps.id

    context.user_data.clear()

    await msg.edit_text(
        f"✅ <b>VPS terdaftar!</b>\n\n"
        f"Label   : <code>{label}</code>\n"
        f"Host    : <code>{host}:{port}</code>\n"
        f"User    : <code>{ssh_user}</code>\n"
        f"OS      : {info}\n\n"
        f"Sekarang install stack VPN-nya:",
        parse_mode=ParseMode.HTML,
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton("🚀 Install Sekarang", callback_data=f"vps:install:{vps_id}")],
            [InlineKeyboardButton("⏱ Nanti Saja", callback_data="menu:main")],
        ]),
    )
    return ConversationHandler.END


async def add_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    context.user_data.clear()
    if update.message:
        await update.message.reply_text("Batal. Kembali ke menu utama /start.")
    elif update.callback_query:
        await update.callback_query.answer("Batal")
        await update.callback_query.edit_message_text(
            "Batal.", reply_markup=back_only(),
        )
    return ConversationHandler.END


def register(app) -> None:
    # ConversationHandler for wizard
    wizard = ConversationHandler(
        entry_points=[CallbackQueryHandler(add_start, pattern=r"^vps:add$")],
        states={
            ADD_LABEL:     [MessageHandler(filters.TEXT & ~filters.COMMAND, add_label)],
            ADD_HOST:      [MessageHandler(filters.TEXT & ~filters.COMMAND, add_host)],
            ADD_PORT:      [MessageHandler(filters.TEXT & ~filters.COMMAND, add_port)],
            ADD_USER:      [MessageHandler(filters.TEXT & ~filters.COMMAND, add_user)],
            ADD_CRED_TYPE: [CallbackQueryHandler(add_cred_type, pattern=r"^addvps:cred:")],
            ADD_CRED:      [MessageHandler(filters.TEXT & ~filters.COMMAND, add_cred)],
        },
        fallbacks=[
            CommandHandler("cancel", add_cancel),
            CommandHandler("start", add_cancel),
        ],
        allow_reentry=True,
    )
    app.add_handler(wizard)
    app.add_handler(CallbackQueryHandler(vps_router, pattern=r"^vps:"))

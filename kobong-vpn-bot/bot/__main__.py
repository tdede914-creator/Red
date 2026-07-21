"""KOBONG VPN BOT entry point.

Starts:
    1. SQLite/Postgres schema init
    2. Telegram bot polling
    3. Background Pakasir payment poller (no webhook)

Run:
    python -m bot
"""
from __future__ import annotations

import asyncio
import logging
import signal
import sys

from telegram.ext import Application, ApplicationBuilder

from .banner import BANNER, BRAND_NAME, BRAND_VERSION
from .config import settings
from .db import init_db
from .handlers import payment as h_payment
from .handlers import protocol_stub as h_proto
from .handlers import ssh_account as h_ssh
from .handlers import start as h_start
from .handlers import vps as h_vps
from .handlers import zivpn_account as h_zivpn
from .payment_poller import PaymentPoller
from .ssh_client import SSHConnectionPool


def _setup_logging() -> None:
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=settings.log_level,
        stream=sys.stdout,
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("telegram.ext").setLevel(logging.INFO)
    logging.getLogger("asyncssh").setLevel(logging.WARNING)

    # Silence noisy PTBUserWarning about per_message=False on
    # ConversationHandler + CallbackQueryHandler mix. Our design
    # is intentional (we mix message and callback flows), and PTB
    # docs confirm per_message=False is correct in that case.
    import warnings
    try:
        from telegram.warnings import PTBUserWarning
        warnings.filterwarnings("ignore", category=PTBUserWarning)
    except ImportError:
        pass


async def _run() -> None:
    log = logging.getLogger("kobong")
    log.info("\n%s", BANNER)
    log.info("%s v%s starting up…", BRAND_NAME, BRAND_VERSION)

    await init_db()

    app: Application = (
        ApplicationBuilder()
        .token(settings.bot_token)
        .concurrent_updates(True)
        .build()
    )

    # Shared resources on app.bot_data (accessible in handlers via context)
    app.bot_data["ssh_pool"] = SSHConnectionPool()

    # Register handlers — order matters for pattern precedence:
    #   ConversationHandlers (with specific entry patterns) must be first,
    #   then plain callback routers, then the protocol_stub catch-all.
    h_start.register(app)     # /start, menu:*
    h_vps.register(app)       # vps:*  + add wizard
    h_ssh.register(app)       # ssh:*  (full CRUD)
    h_zivpn.register(app)     # zivpn:* (full CRUD)
    h_payment.register(app)   # pay:*
    h_proto.register(app)     # fallback for vmess/vless/trojan/shadow/openvpn/slowdns

    # Payment poller (polling-based, no webhook)
    poller = PaymentPoller(app.bot)
    app.bot_data["poller"] = poller

    await app.initialize()
    await app.start()
    await app.updater.start_polling(drop_pending_updates=True)
    await poller.start()

    log.info("✅ Bot online. Admin IDs: %s", settings.admin_ids or "(none)")
    log.info(
        "💰 Pakasir: %s",
        "ENABLED (polling every 10s)" if settings.is_pakasir_enabled else "disabled",
    )
    log.info("🔐 SSH pool size: %d", settings.ssh_pool_size)

    stop_event = asyncio.Event()

    def _handle_signal() -> None:
        log.info("Shutdown signal received")
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _handle_signal)
        except NotImplementedError:
            pass  # Windows

    await stop_event.wait()

    log.info("Shutting down…")
    await poller.stop()
    await app.updater.stop()
    await app.stop()
    await app.shutdown()
    log.info("Goodbye 👋")


def main() -> None:
    _setup_logging()
    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

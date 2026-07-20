"""KOBONG VPN BOT entry point.

Starts:
    1. SQLite/Postgres schema init
    2. Telegram bot polling (async)
    3. aiohttp webhook server for Pakasir callbacks (in same event loop)

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
from .handlers import start as h_start
from .handlers import vps as h_vps
from .webhook_server import WebhookServer


def _setup_logging() -> None:
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=settings.log_level,
        stream=sys.stdout,
    )
    # Silence noisy libs
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("telegram.ext").setLevel(logging.INFO)


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

    # Register handlers (order matters: specific patterns before catch-all)
    h_start.register(app)
    h_vps.register(app)
    h_payment.register(app)
    h_proto.register(app)  # catch-all for protocol callbacks (registered last)

    # Webhook server for Pakasir
    web = WebhookServer(app.bot)

    await app.initialize()
    await app.start()
    await app.updater.start_polling(drop_pending_updates=True)
    await web.start()

    log.info("✅ Bot is online. Admin IDs: %s", settings.admin_ids or "(none)")
    log.info(
        "💰 Pakasir: %s",
        "ENABLED" if settings.is_pakasir_enabled else "disabled (fill PAKASIR_* env)",
    )

    # Wait for shutdown signal
    stop_event = asyncio.Event()

    def _handle_signal() -> None:
        log.info("Shutdown signal received")
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _handle_signal)
        except NotImplementedError:
            # Windows doesn't support add_signal_handler
            pass

    await stop_event.wait()

    log.info("Shutting down…")
    await web.stop()
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

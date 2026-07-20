"""Orchestrate the remote install of the KOBONG stack on a target VPS.

Flow:
    1. Read local scripts/kobong-install.sh + scripts/install_zivpn.sh
    2. Upload them to /tmp on the VPS via SFTP
    3. Execute kobong-install.sh streaming stdout back to Telegram
    4. Parse a small set of well-known progress markers ([✓], [callback])
       to update a nicely-formatted progress message
    5. On success: mark VPS status=ACTIVE, save installed_protocols
    6. On failure: mark VPS status=ERROR, keep last 30 log lines for debug
"""
from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Awaitable, Callable, Optional

from sqlalchemy import select

from .db import get_session
from .models import VPS, Protocol, VPSStatus
from .ssh_client import KobongSSH, SSHError

log = logging.getLogger(__name__)

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"

# Progress markers emitted by kobong-install.sh
_STAGE_REGEX = re.compile(r"MENJALANKAN\s+(\w+)|====\s+(\w+)\s+SELESAI")
_OK_REGEX = re.compile(r"\[✓\]\s*(.+)")


class InstallProgress:
    """Tracks structured progress + accumulates a rolling log tail."""

    STAGES = [
        ("base_packages",  "📦 Base packages"),
        ("ssl",            "🔒 SSL certificate"),
        ("ssh",            "🔐 SSH + Dropbear"),
        ("xray",           "⚡ Xray core"),
        ("zivpn",          "🚀 ZIVPN UDP"),
    ]

    def __init__(self):
        self.done: set[str] = set()
        self.current: Optional[str] = None
        self.log_tail: list[str] = []
        self.error: Optional[str] = None

    def observe(self, line: str) -> bool:
        """Feed one log line. Returns True if progress state changed."""
        line = line.strip()
        if not line:
            return False

        # Rolling tail (last 20 lines for debug)
        self.log_tail.append(line)
        if len(self.log_tail) > 20:
            self.log_tail.pop(0)

        changed = False

        # Fast-check for stage keywords in our install script
        for key, _label in self.STAGES:
            if f"MENJALANKAN {key}" in line or f"[{key.upper()}]" in line:
                if self.current != key:
                    self.current = key
                    changed = True
            elif key in line.lower() and "done" in line.lower():
                if key not in self.done:
                    self.done.add(key)
                    changed = True

        # Detect explicit callback stages emitted via curl
        if "callback" in line and "done" in line:
            for key, _ in self.STAGES:
                if key in line and key not in self.done:
                    self.done.add(key)
                    changed = True

        # Look for [✓] success markers
        m = _OK_REGEX.search(line)
        if m:
            msg = m.group(1).lower()
            for key, _ in self.STAGES:
                if key in msg and key not in self.done:
                    self.done.add(key)
                    changed = True

        # Detect error
        if "[✗]" in line or "ERROR:" in line or "FATAL:" in line:
            self.error = line
            changed = True

        return changed

    def render(self, vps_label: str, is_done: bool = False) -> str:
        """Build a pretty progress message for Telegram."""
        lines = [f"<b>🚀 Instalasi KOBONG Stack di {vps_label}</b>\n"]
        for key, label in self.STAGES:
            if key in self.done:
                mark = "✅"
            elif key == self.current:
                mark = "⏳"
            else:
                mark = "⬜"
            lines.append(f"{mark} {label}")

        if self.error and not is_done:
            lines.append(f"\n❌ <b>Error:</b> <code>{_escape(self.error)}</code>")
        elif is_done and not self.error:
            lines.append("\n✅ <b>Selesai!</b>")

        if self.log_tail and (self.error or is_done):
            lines.append("\n<b>Log terakhir:</b>")
            tail = "\n".join(self.log_tail[-6:])
            lines.append(f"<pre>{_escape(tail)}</pre>")

        return "\n".join(lines)


def _escape(text: str) -> str:
    """Escape HTML-special chars for Telegram."""
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
    )


class InstallOrchestrator:
    """Coordinates the remote install with periodic Telegram updates."""

    UPDATE_INTERVAL = 3.0  # seconds between edit_message updates

    def __init__(
        self,
        vps: VPS,
        install_mode: str = "full",
        install_zivpn: bool = True,
        zivpn_passwords: str = "zi",
        zivpn_port: int = 5667,
        domain: Optional[str] = None,
    ):
        self.vps = vps
        self.install_mode = install_mode
        self.install_zivpn = install_zivpn
        self.zivpn_passwords = zivpn_passwords
        self.zivpn_port = zivpn_port
        self.domain = domain
        self.progress = InstallProgress()

    async def run(
        self,
        edit_message: Callable[[str], Awaitable[None]],
    ) -> tuple[bool, str]:
        """Execute install. Returns (success, summary_or_error).

        `edit_message` should be an async callable that updates the Telegram
        message shown to the user (throttled internally).
        """
        # Verify scripts exist locally
        main_sh = SCRIPTS_DIR / "kobong-install.sh"
        zivpn_sh = SCRIPTS_DIR / "install_zivpn.sh"
        for p in (main_sh, zivpn_sh):
            if not p.exists():
                return False, f"Script tidak ditemukan: {p.name}"

        # Mark VPS installing
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.id == self.vps.id)
            )
            v = result.scalar_one()
            v.status = VPSStatus.INSTALLING

        await edit_message(self.progress.render(self.vps.label))

        last_update = 0.0
        try:
            async with KobongSSH(self.vps, timeout=60.0) as ssh:
                await edit_message(
                    self.progress.render(self.vps.label) +
                    "\n<i>🔗 Terhubung. Upload script…</i>"
                )
                await ssh.upload(str(main_sh), "/tmp/kobong-install.sh")
                await ssh.upload(str(zivpn_sh), "/tmp/install_zivpn.sh")
                await ssh.run("chmod +x /tmp/kobong-install.sh /tmp/install_zivpn.sh")

                # Build env prefix for the install script
                env_parts = [
                    f"INSTALL_MODE={self.install_mode}",
                    f"INSTALL_ZIVPN={'yes' if self.install_zivpn else 'no'}",
                    f"ZIVPN_PASSWORDS='{self.zivpn_passwords}'",
                    f"ZIVPN_PORT={self.zivpn_port}",
                ]
                if self.domain:
                    env_parts.append(f"DOMAIN='{self.domain}'")
                env_prefix = " ".join(env_parts)

                cmd = f"{env_prefix} bash /tmp/kobong-install.sh"

                async def on_line(line: str) -> None:
                    nonlocal last_update
                    changed = self.progress.observe(line)
                    now = asyncio.get_event_loop().time()
                    if changed and (now - last_update) >= self.UPDATE_INTERVAL:
                        last_update = now
                        try:
                            await edit_message(self.progress.render(self.vps.label))
                        except Exception as e:  # noqa: BLE001
                            log.debug("edit_message failed: %s", e)

                # Wrap sync on_line into scheduling
                pending = asyncio.Queue()

                def line_cb(line: str) -> None:
                    pending.put_nowait(line)

                consumer_task = asyncio.create_task(_consume_lines(pending, on_line))

                exit_code = await ssh.run_stream(
                    cmd, on_line=line_cb, timeout=1800.0,  # 30 min hard cap
                )
                pending.put_nowait(None)  # sentinel
                await consumer_task

                if exit_code != 0:
                    self.progress.error = f"Install script exited with code {exit_code}"

                # Read install manifest for details
                manifest = ""
                try:
                    manifest = await ssh.read_file("/etc/kobong/install.json")
                except SSHError:
                    pass

        except SSHError as e:
            log.exception("SSH error during install")
            self.progress.error = str(e)
            await self._mark_error(str(e))
            await edit_message(self.progress.render(self.vps.label, is_done=True))
            return False, str(e)

        except Exception as e:  # noqa: BLE001
            log.exception("Unexpected error during install")
            self.progress.error = f"Unexpected: {e}"
            await self._mark_error(str(e))
            await edit_message(self.progress.render(self.vps.label, is_done=True))
            return False, str(e)

        # Success?
        if self.progress.error:
            await self._mark_error(self.progress.error)
            await edit_message(self.progress.render(self.vps.label, is_done=True))
            return False, self.progress.error

        # Update VPS record
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.id == self.vps.id)
            )
            v = result.scalar_one()
            v.status = VPSStatus.ACTIVE
            v.installed_at = datetime.now(timezone.utc)
            v.add_protocol(Protocol.SSH)
            if self.install_mode in {"full", "xray"}:
                v.add_protocol(Protocol.VMESS)
                v.add_protocol(Protocol.VLESS)
                v.add_protocol(Protocol.TROJAN)
                v.add_protocol(Protocol.SHADOWSOCKS)
            if self.install_zivpn:
                v.add_protocol(Protocol.ZIVPN)

        summary = self.progress.render(self.vps.label, is_done=True)
        if manifest:
            summary += f"\n<i>Manifest tersimpan di /etc/kobong/install.json</i>"
        await edit_message(summary)
        return True, "installed"

    async def _mark_error(self, msg: str) -> None:
        async with get_session() as session:
            result = await session.execute(
                select(VPS).where(VPS.id == self.vps.id)
            )
            v = result.scalar_one_or_none()
            if v:
                v.status = VPSStatus.ERROR
                v.notes = msg[:500]


async def _consume_lines(
    queue: asyncio.Queue,
    handler: Callable[[str], Awaitable[None]],
) -> None:
    """Drain the queue and call handler for each line."""
    while True:
        line = await queue.get()
        if line is None:
            return
        try:
            await handler(line)
        except Exception:  # noqa: BLE001
            log.exception("Line handler error")

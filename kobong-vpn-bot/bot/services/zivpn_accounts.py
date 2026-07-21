"""ZIVPN account management on remote VPS.

ZIVPN authentication is a simple list of passwords in
/etc/kobong/zivpn/config.json:

    {
      "auth": {
        "mode": "passwords",
        "config": ["pw1", "pw2", "pw3"]
      }
    }

Adding/removing an account = editing that array + restarting the service.
We track ownership in our DB (accounts table) with:

    * username = a label (e.g. 'client-budi')
    * password = the actual auth string
    * expires_at = we handle expiry on OUR side (poll job in M5)
"""
from __future__ import annotations

import json
import logging
import re
import secrets
import string
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select

from ..db import get_session
from ..models import VPS, Account, Protocol
from ..ssh_client import KobongSSH, SSHError

log = logging.getLogger(__name__)

CONFIG_PATH = "/etc/kobong/zivpn/config.json"
SERVICE_NAME = "kobong-zivpn"

USERNAME_REGEX = re.compile(r"^[a-z0-9][a-z0-9_-]{2,30}$")


class ZIVPNError(Exception):
    pass


@dataclass
class ZIVPNCreateResult:
    username: str
    password: str
    host: str
    port: int
    port_range: str
    expires: date


def _random_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def validate_username(username: str) -> None:
    if not USERNAME_REGEX.match(username):
        raise ZIVPNError(
            "Label 3-31 karakter, huruf kecil/angka, dash/underscore."
        )


async def _read_config(ssh: KobongSSH) -> dict:
    try:
        raw = await ssh.read_file(CONFIG_PATH)
        return json.loads(raw)
    except SSHError as e:
        raise ZIVPNError(f"Gagal baca config ZIVPN: {e}") from e
    except json.JSONDecodeError as e:
        raise ZIVPNError(f"Config ZIVPN corrupt: {e}") from e


async def _write_config(ssh: KobongSSH, cfg: dict) -> None:
    text = json.dumps(cfg, indent=2)
    try:
        await ssh.write_file(CONFIG_PATH, text, mode="600")
    except SSHError as e:
        raise ZIVPNError(f"Gagal tulis config ZIVPN: {e}") from e


async def _restart_service(ssh: KobongSSH) -> None:
    try:
        await ssh.run(f"systemctl restart {SERVICE_NAME}", timeout=20)
    except SSHError as e:
        raise ZIVPNError(f"Gagal restart ZIVPN: {e}") from e


async def _passwords(cfg: dict) -> list[str]:
    return list(cfg.get("auth", {}).get("config", []))


# ── CRUD ────────────────────────────────────────────────────────────
async def create_account(
    vps: VPS,
    username: str,
    duration_days: int,
    password: Optional[str] = None,
) -> ZIVPNCreateResult:
    validate_username(username)
    if duration_days <= 0 or duration_days > 365:
        raise ZIVPNError("Durasi harus 1-365 hari")
    if not password:
        password = _random_password()

    try:
        async with KobongSSH(vps, timeout=30.0) as ssh:
            cfg = await _read_config(ssh)
            passwords = await _passwords(cfg)

            if password in passwords:
                raise ZIVPNError("Password sudah dipakai akun lain, generate ulang.")

            passwords.append(password)
            cfg.setdefault("auth", {})["config"] = passwords
            await _write_config(ssh, cfg)
            await _restart_service(ssh)

            # Detect port from listen field
            listen = cfg.get("listen", ":5667")
            port = int(listen.split(":")[-1])
    except SSHError as e:
        raise ZIVPNError(f"SSH error: {e}") from e

    exp = date.today() + timedelta(days=duration_days)

    async with get_session() as session:
        # Check unique username per vps
        result = await session.execute(
            select(Account).where(
                Account.vps_id == vps.id,
                Account.protocol == Protocol.ZIVPN,
                Account.username == username,
            )
        )
        if result.scalar_one_or_none():
            # Rollback config change to avoid orphan password
            try:
                async with KobongSSH(vps) as ssh:
                    cfg = await _read_config(ssh)
                    plist = await _passwords(cfg)
                    if password in plist:
                        plist.remove(password)
                        cfg["auth"]["config"] = plist
                        await _write_config(ssh, cfg)
                        await _restart_service(ssh)
            except Exception:  # noqa: BLE001
                pass
            raise ZIVPNError(f"Label '{username}' sudah dipakai di VPS ini")

        acc = Account(
            vps_id=vps.id,
            protocol=Protocol.ZIVPN,
            username=username,
            password=password,
            expires_at=datetime.combine(exp, datetime.min.time(), tzinfo=timezone.utc),
        )
        session.add(acc)

    log.info("ZIVPN password added on %s: label=%s (exp %s)", vps.host, username, exp)

    return ZIVPNCreateResult(
        username=username,
        password=password,
        host=vps.domain or vps.host,
        port=port,
        port_range="6000-19999",
        expires=exp,
    )


async def delete_account(vps: VPS, username: str) -> None:
    validate_username(username)

    # Look up password in DB
    async with get_session() as session:
        result = await session.execute(
            select(Account).where(
                Account.vps_id == vps.id,
                Account.protocol == Protocol.ZIVPN,
                Account.username == username,
            )
        )
        acc = result.scalar_one_or_none()
        if not acc:
            raise ZIVPNError("Akun tidak ditemukan di database bot")
        password = acc.password
        await session.delete(acc)

    if not password:
        return

    try:
        async with KobongSSH(vps, timeout=30.0) as ssh:
            cfg = await _read_config(ssh)
            plist = await _passwords(cfg)
            if password in plist:
                plist.remove(password)
                cfg["auth"]["config"] = plist or ["kobong-placeholder"]
                await _write_config(ssh, cfg)
                await _restart_service(ssh)
    except SSHError as e:
        raise ZIVPNError(f"SSH error saat hapus: {e}") from e


async def list_accounts(vps: VPS) -> list[Account]:
    async with get_session() as session:
        result = await session.execute(
            select(Account)
            .where(Account.vps_id == vps.id, Account.protocol == Protocol.ZIVPN)
            .order_by(Account.expires_at.desc())
        )
        return list(result.scalars())


async def restart_service(vps: VPS) -> None:
    async with KobongSSH(vps, timeout=15.0) as ssh:
        await _restart_service(ssh)


def format_config(res: ZIVPNCreateResult) -> str:
    return (
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "        ZIVPN ACCOUNT\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Label      : {res.username}\n"
        f"Password   : {res.password}\n"
        f"Host       : {res.host}\n"
        f"Port       : {res.port} (UDP)\n"
        f"Port Range : {res.port_range} (UDP)\n"
        f"Obfs       : zivpn\n"
        f"Berlaku    : sampai {res.expires:%d %b %Y}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "\n📱 Buka app ZIVPN di HP:\n"
        "   Play Store → 'ZIVPN'\n"
        "   Masukkan Host + Password + Port di atas."
    )

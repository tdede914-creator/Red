"""SSH account CRUD on remote VPS.

Uses standard Linux user management (useradd, chpasswd, chage) executed
over SSH. Users are created with:

    * shell:      /bin/false (login-restricted, only usable for tunneling)
    * home dir:   none (--no-create-home)
    * expiry:     `chage -E <YYYY-MM-DD>` for auto-lock on renewal expiry
    * group:      'kobong-ssh' (marker so we can safely list/purge them)

Ports assumed installed by kobong-install.sh:
    * 22 / 143 / 109  → SSH & Dropbear
    * 80 / 443        → Nginx / HAProxy (for WS-TLS bypass in future)
"""
from __future__ import annotations

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

USERNAME_REGEX = re.compile(r"^[a-z][a-z0-9_-]{2,15}$")
KOBONG_GROUP = "kobong-ssh"


class SSHAccountError(Exception):
    """Raised for invalid input / remote failures."""


@dataclass
class SSHCreateResult:
    username: str
    password: str
    host: str
    ssh_port: int
    dropbear_ports: list[int]
    ws_ports: list[int]
    expires: date


def _random_password(length: int = 10) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def validate_username(username: str) -> None:
    if not USERNAME_REGEX.match(username):
        raise SSHAccountError(
            "Username harus 3-16 karakter, huruf kecil, angka, dash/underscore, "
            "diawali huruf."
        )


# ── Remote operations ───────────────────────────────────────────────
async def ensure_group(ssh: KobongSSH) -> None:
    """Ensure the kobong-ssh group exists (idempotent)."""
    await ssh.run(
        f"getent group {KOBONG_GROUP} >/dev/null || groupadd --system {KOBONG_GROUP}"
    )


async def create_account(
    vps: VPS,
    username: str,
    duration_days: int,
    password: Optional[str] = None,
    ip_limit: int = 2,
) -> SSHCreateResult:
    validate_username(username)
    if duration_days <= 0 or duration_days > 365:
        raise SSHAccountError("Durasi harus 1-365 hari")
    if not password:
        password = _random_password()

    exp = date.today() + timedelta(days=duration_days)
    exp_str = exp.strftime("%Y-%m-%d")

    try:
        async with KobongSSH(vps, timeout=30.0) as ssh:
            await ensure_group(ssh)

            # Check if user already exists
            r = await ssh.run(f"id -u {username}", check=False, timeout=10)
            if r.exit_status == 0:
                raise SSHAccountError(f"Username '{username}' sudah ada di VPS")

            # Create user, restricted shell, member of kobong-ssh group
            await ssh.run(
                f"useradd -m -s /bin/false -g {KOBONG_GROUP} "
                f"-e {exp_str} {username}",
                timeout=15,
            )
            # Set password (chpasswd from stdin — no shell escaping issues)
            await ssh.run(
                "chpasswd",
                input_data=f"{username}:{password}\n",
                timeout=10,
            )
            # Belt-and-braces: also set expiry with chage
            await ssh.run(f"chage -E {exp_str} {username}", timeout=10)

            log.info("SSH account created on %s: %s (exp %s)", vps.host, username, exp_str)

    except SSHError as e:
        raise SSHAccountError(f"Gagal buat akun di VPS: {e}") from e

    # Persist to DB
    async with get_session() as session:
        acc = Account(
            vps_id=vps.id,
            protocol=Protocol.SSH,
            username=username,
            password=password,
            ip_limit=ip_limit,
            expires_at=datetime.combine(exp, datetime.min.time(), tzinfo=timezone.utc),
        )
        session.add(acc)

    return SSHCreateResult(
        username=username,
        password=password,
        host=vps.domain or vps.host,
        ssh_port=vps.port or 22,
        dropbear_ports=[143, 109],
        ws_ports=[80, 8080],
        expires=exp,
    )


async def delete_account(vps: VPS, username: str) -> None:
    validate_username(username)
    try:
        async with KobongSSH(vps, timeout=15.0) as ssh:
            # Kill any active sessions first
            await ssh.run(f"pkill -u {username}", check=False, timeout=5)
            await ssh.run(f"userdel -r {username} 2>/dev/null || userdel {username}",
                          check=False, timeout=10)
    except SSHError as e:
        raise SSHAccountError(f"Gagal hapus akun: {e}") from e

    async with get_session() as session:
        result = await session.execute(
            select(Account).where(
                Account.vps_id == vps.id,
                Account.protocol == Protocol.SSH,
                Account.username == username,
            )
        )
        for acc in result.scalars():
            await session.delete(acc)


async def renew_account(vps: VPS, username: str, extra_days: int) -> date:
    validate_username(username)
    if extra_days <= 0 or extra_days > 365:
        raise SSHAccountError("Durasi renew harus 1-365 hari")

    async with get_session() as session:
        result = await session.execute(
            select(Account).where(
                Account.vps_id == vps.id,
                Account.protocol == Protocol.SSH,
                Account.username == username,
            )
        )
        acc = result.scalar_one_or_none()
        if not acc:
            raise SSHAccountError("Akun tidak ditemukan di database bot")

        # Extend from whichever is later: today or current expiry
        current_exp = acc.expires_at.date() if acc.expires_at else date.today()
        base = max(current_exp, date.today())
        new_exp = base + timedelta(days=extra_days)
        acc.expires_at = datetime.combine(new_exp, datetime.min.time(), tzinfo=timezone.utc)

    exp_str = new_exp.strftime("%Y-%m-%d")
    try:
        async with KobongSSH(vps, timeout=15.0) as ssh:
            await ssh.run(f"chage -E {exp_str} {username}", timeout=10)
            # Ensure user isn't already locked
            await ssh.run(f"passwd -u {username} 2>/dev/null", check=False, timeout=5)
    except SSHError as e:
        raise SSHAccountError(f"Gagal renew di VPS: {e}") from e

    return new_exp


async def list_accounts(vps: VPS) -> list[Account]:
    async with get_session() as session:
        result = await session.execute(
            select(Account)
            .where(Account.vps_id == vps.id, Account.protocol == Protocol.SSH)
            .order_by(Account.expires_at.desc())
        )
        return list(result.scalars())


def format_config(res: SSHCreateResult) -> str:
    """User-friendly config text to paste into their SSH tunnel app."""
    return (
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "         SSH ACCOUNT\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Host       : {res.host}\n"
        f"Username   : {res.username}\n"
        f"Password   : {res.password}\n"
        f"SSH Port   : {res.ssh_port}\n"
        f"Dropbear   : {', '.join(str(p) for p in res.dropbear_ports)}\n"
        f"WebSocket  : {', '.join(str(p) for p in res.ws_ports)}\n"
        f"Berlaku    : sampai {res.expires:%d %b %Y}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    )

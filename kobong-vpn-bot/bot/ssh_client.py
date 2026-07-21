"""Async SSH wrapper around asyncssh.

Provides:
    * KobongSSH context manager for one-shot connections
    * SSHConnectionPool for connection reuse across handlers
    * run() / run_stream() helpers

Credentials are decrypted just-in-time from the VPS model — never held
in memory longer than needed.
"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator, Callable, Optional

import asyncssh

from .config import settings
from .crypto import decrypt
from .models import VPS

log = logging.getLogger(__name__)

# asyncssh has quite verbose logs — silence unless debug
logging.getLogger("asyncssh").setLevel(logging.WARNING)


class SSHError(Exception):
    """Wrap SSH errors so handlers can catch a single exception type."""


class KobongSSH:
    """Single-connection SSH context.

    Usage:
        async with KobongSSH(vps) as ssh:
            result = await ssh.run("whoami")
            print(result.stdout)
    """

    def __init__(self, vps: VPS, timeout: float = 30.0):
        self.vps = vps
        self.timeout = timeout
        self._conn: Optional[asyncssh.SSHClientConnection] = None

    async def __aenter__(self) -> "KobongSSH":
        try:
            kwargs: dict = {
                "host": self.vps.host,
                "port": self.vps.port,
                "username": self.vps.ssh_user,
                "known_hosts": None,   # trust on first use
                "connect_timeout": self.timeout,
            }
            if self.vps.ssh_password_enc:
                kwargs["password"] = decrypt(self.vps.ssh_password_enc)
            elif self.vps.ssh_key_enc:
                kwargs["client_keys"] = [
                    asyncssh.import_private_key(decrypt(self.vps.ssh_key_enc))
                ]
            else:
                raise SSHError("VPS has no SSH credentials configured")

            self._conn = await asyncio.wait_for(
                asyncssh.connect(**kwargs), timeout=self.timeout + 5
            )
            return self
        except asyncssh.PermissionDenied as e:
            raise SSHError(f"SSH login rejected: {e}") from e
        except (asyncssh.Error, asyncio.TimeoutError, OSError) as e:
            raise SSHError(f"SSH connection failed: {e}") from e

    async def __aexit__(self, *args) -> None:
        if self._conn:
            self._conn.close()
            await self._conn.wait_closed()
            self._conn = None

    async def run(
        self,
        command: str,
        *,
        check: bool = True,
        input_data: Optional[str] = None,
        timeout: float = 120.0,
    ) -> asyncssh.SSHCompletedProcess:
        """Execute a command and return the finished process."""
        assert self._conn is not None, "Not connected"
        try:
            result = await asyncio.wait_for(
                self._conn.run(command, input=input_data, check=False),
                timeout=timeout,
            )
        except asyncio.TimeoutError as e:
            raise SSHError(f"Command timed out after {timeout}s: {command[:60]}") from e
        except asyncssh.Error as e:
            raise SSHError(f"SSH error: {e}") from e

        if check and result.exit_status != 0:
            stderr = (result.stderr or "").strip()[:500]
            raise SSHError(
                f"Command failed (exit={result.exit_status}): {command[:60]}\n"
                f"stderr: {stderr}"
            )
        return result

    async def run_stream(
        self,
        command: str,
        *,
        on_line: Callable[[str], None],
        timeout: float = 900.0,
    ) -> int:
        """Execute a command and stream stdout+stderr line-by-line to `on_line`.

        Returns the exit status. Used for long installs where we want to
        forward progress to Telegram.
        """
        assert self._conn is not None, "Not connected"
        try:
            proc = await self._conn.create_process(
                command, stderr=asyncssh.STDOUT
            )
        except asyncssh.Error as e:
            raise SSHError(f"Failed to start process: {e}") from e

        async def _pump():
            async for line in proc.stdout:
                on_line(line.rstrip("\n"))

        try:
            await asyncio.wait_for(_pump(), timeout=timeout)
            await proc.wait_closed()
        except asyncio.TimeoutError as e:
            proc.terminate()
            raise SSHError(f"Stream timed out after {timeout}s") from e
        return proc.returncode or 0

    async def upload(self, local_path: str, remote_path: str) -> None:
        """Upload a single file via SFTP."""
        assert self._conn is not None
        try:
            async with self._conn.start_sftp_client() as sftp:
                await sftp.put(local_path, remote_path)
        except asyncssh.Error as e:
            raise SSHError(f"SFTP upload failed: {e}") from e

    async def write_file(self, remote_path: str, content: str, mode: str = "644") -> None:
        """Write a small text file to remote path (uses SFTP)."""
        assert self._conn is not None
        try:
            async with self._conn.start_sftp_client() as sftp:
                async with sftp.open(remote_path, "w") as f:
                    await f.write(content)
            await self.run(f"chmod {mode} {remote_path}")
        except asyncssh.Error as e:
            raise SSHError(f"SFTP write failed: {e}") from e

    async def read_file(self, remote_path: str) -> str:
        """Read remote text file."""
        assert self._conn is not None
        try:
            async with self._conn.start_sftp_client() as sftp:
                async with sftp.open(remote_path, "r") as f:
                    return await f.read()
        except asyncssh.Error as e:
            raise SSHError(f"SFTP read failed: {e}") from e


# ── Connection pool (semaphore-limited) ─────────────────────────────
class SSHConnectionPool:
    """Global semaphore to cap concurrent SSH sessions across the bot.

    Usage:
        pool = SSHConnectionPool()
        async with pool.acquire(vps) as ssh:
            await ssh.run("uptime")
    """

    def __init__(self, max_concurrent: int = None):  # type: ignore[assignment]
        self._sem = asyncio.Semaphore(max_concurrent or settings.ssh_pool_size)

    @asynccontextmanager
    async def acquire(self, vps: VPS) -> AsyncIterator[KobongSSH]:
        async with self._sem:
            async with KobongSSH(vps) as ssh:
                yield ssh


# ── Quick verify (for wizard) ───────────────────────────────────────
async def verify_credentials(
    host: str,
    port: int,
    user: str,
    password: Optional[str] = None,
    private_key: Optional[str] = None,
    timeout: float = 15.0,
) -> tuple[bool, str]:
    """Test SSH login using raw credentials (before saving to DB).

    Returns (ok, message). On success, message contains OS info.
    """
    try:
        kwargs: dict = {
            "host": host,
            "port": port,
            "username": user,
            "known_hosts": None,
            "connect_timeout": timeout,
        }
        if password:
            kwargs["password"] = password
        elif private_key:
            kwargs["client_keys"] = [asyncssh.import_private_key(private_key)]
        else:
            return False, "No credentials provided"

        async with asyncssh.connect(**kwargs) as conn:
            os_info = await conn.run(
                "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'",
                check=False,
            )
            arch = await conn.run("uname -m", check=False)
            return True, f"{(os_info.stdout or '').strip()} ({(arch.stdout or '').strip()})"
    except asyncssh.PermissionDenied:
        return False, "Login ditolak — cek user & password"
    except (asyncssh.Error, asyncio.TimeoutError, OSError) as e:
        return False, f"Gagal konek: {e}"

"""Configuration loader with strict validation.

All settings are loaded from environment variables (.env in dev, real env in
production). Missing or malformed values cause the bot to fail fast at boot
rather than at first use.
"""
from __future__ import annotations

from pathlib import Path
from typing import List, Optional

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Telegram ────────────────────────────────────────────────────
    bot_token: str = Field(..., min_length=20, description="Token from @BotFather")
    bot_username: str = Field("KobongVpnBot", description="Bot username without @")
    super_admin_ids: str = Field("", description="Comma-separated admin user IDs")
    notify_chat_id: Optional[int] = Field(None, description="Chat ID for system notifications")

    # ── Encryption ──────────────────────────────────────────────────
    fernet_key: str = Field(..., min_length=32, description="Fernet key for VPS creds encryption")

    # ── Database ────────────────────────────────────────────────────
    database_url: str = Field(
        "sqlite+aiosqlite:///data/kobong.db",
        description="SQLAlchemy async database URL",
    )

    # ── Pakasir (polling-based, no webhook) ─────────────────────────
    pakasir_slug: str = Field("", description="Pakasir project slug")
    pakasir_api_key: str = Field("", description="Pakasir API key")
    pakasir_method: str = Field("qris", description="Default Pakasir payment method")
    pakasir_base_url: str = Field(
        "https://app.pakasir.com",
        description="Pakasir API base URL (only override for testing)",
    )

    # ── Behavior ────────────────────────────────────────────────────
    currency: str = Field("Rp", description="Currency label")
    default_price_ssh: int = Field(5000, ge=500)
    default_price_xray: int = Field(8000, ge=500)
    default_price_zivpn: int = Field(10000, ge=500)
    default_duration_days: int = Field(30, ge=1, le=365)
    ssh_pool_size: int = Field(10, ge=1, le=100)
    log_level: str = Field("INFO", pattern=r"^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$")

    # ── Derived helpers ─────────────────────────────────────────────
    @property
    def admin_ids(self) -> List[int]:
        """Parsed list of super admin Telegram user IDs."""
        if not self.super_admin_ids.strip():
            return []
        return [
            int(x.strip())
            for x in self.super_admin_ids.split(",")
            if x.strip().isdigit()
        ]

    @property
    def data_dir(self) -> Path:
        """Data directory (auto-created)."""
        p = Path("data")
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def is_pakasir_enabled(self) -> bool:
        return bool(self.pakasir_slug and self.pakasir_api_key)

    @field_validator("fernet_key")
    @classmethod
    def _check_fernet(cls, v: str) -> str:
        if v == "CHANGE_ME_TO_A_REAL_FERNET_KEY":
            raise ValueError(
                "FERNET_KEY is still the placeholder. Generate one with:\n"
                "  python -c \"from cryptography.fernet import Fernet; "
                "print(Fernet.generate_key().decode())\""
            )
        return v


# Singleton — import `settings` from anywhere in the codebase
settings = Settings()  # type: ignore[call-arg]

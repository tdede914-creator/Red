"""SQLAlchemy ORM models.

Table overview:
    users     — Bot users (bot admins, resellers). NOT VPN account users.
    vps       — Registered target VPS servers (owned by a bot user).
    accounts  — VPN accounts (SSH/VMess/VLESS/Trojan/Shadow/ZIVPN) on a VPS.
    orders    — Payment orders (top-up saldo).
    products  — Sellable products / plans (per-VPS pricing).

Relationships:
    User 1─N VPS 1─N Account
    User 1─N Order
"""
from __future__ import annotations

import enum
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum as SAEnum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


# ── Enums ───────────────────────────────────────────────────────────
class UserRole(str, enum.Enum):
    SUPER_ADMIN = "super_admin"  # bot owner, full control
    RESELLER = "reseller"        # can register VPS + create accounts, pays via Pakasir
    CLIENT = "client"            # end-user of a reseller (future use)
    BANNED = "banned"


class Protocol(str, enum.Enum):
    SSH = "ssh"
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"
    SHADOWSOCKS = "shadowsocks"
    ZIVPN = "zivpn"
    OPENVPN = "openvpn"
    SLOWDNS = "slowdns"


class VPSStatus(str, enum.Enum):
    PENDING = "pending"      # registered but not yet installed
    INSTALLING = "installing"
    ACTIVE = "active"
    ERROR = "error"
    DISABLED = "disabled"


class OrderStatus(str, enum.Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    CANCELED = "canceled"
    EXPIRED = "expired"
    FAILED = "failed"


# ── Users ───────────────────────────────────────────────────────────
class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    telegram_id: Mapped[int] = mapped_column(BigInteger, unique=True, index=True)
    username: Mapped[Optional[str]] = mapped_column(String(64))
    first_name: Mapped[Optional[str]] = mapped_column(String(128))
    role: Mapped[UserRole] = mapped_column(
        SAEnum(UserRole, native_enum=False), default=UserRole.RESELLER
    )
    balance: Mapped[int] = mapped_column(Integer, default=0, doc="Balance in Rupiah")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    last_active_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)

    vps_list: Mapped[List["VPS"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan"
    )
    orders: Mapped[List["Order"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<User id={self.id} tg={self.telegram_id} role={self.role.value}>"


# ── VPS ─────────────────────────────────────────────────────────────
class VPS(Base):
    __tablename__ = "vps"
    __table_args__ = (UniqueConstraint("owner_id", "label", name="uq_vps_owner_label"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    label: Mapped[str] = mapped_column(String(64), doc="Human name, e.g. 'SG1'")
    host: Mapped[str] = mapped_column(String(255), doc="IP or domain")
    port: Mapped[int] = mapped_column(Integer, default=22)
    ssh_user: Mapped[str] = mapped_column(String(64), default="root")

    # Encrypted at rest — use crypto.encrypt/decrypt
    ssh_password_enc: Mapped[Optional[str]] = mapped_column(Text)
    ssh_key_enc: Mapped[Optional[str]] = mapped_column(Text)

    domain: Mapped[Optional[str]] = mapped_column(String(255))
    os_info: Mapped[Optional[str]] = mapped_column(String(128))
    status: Mapped[VPSStatus] = mapped_column(
        SAEnum(VPSStatus, native_enum=False), default=VPSStatus.PENDING
    )
    installed_protocols: Mapped[str] = mapped_column(
        String(255), default="", doc="Comma-separated protocol names"
    )
    notes: Mapped[Optional[str]] = mapped_column(Text)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    installed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    owner: Mapped[User] = relationship(back_populates="vps_list")
    accounts: Mapped[List["Account"]] = relationship(
        back_populates="vps", cascade="all, delete-orphan"
    )

    def has_protocol(self, proto: Protocol) -> bool:
        return proto.value in (self.installed_protocols or "").split(",")

    def add_protocol(self, proto: Protocol) -> None:
        current = set(filter(None, (self.installed_protocols or "").split(",")))
        current.add(proto.value)
        self.installed_protocols = ",".join(sorted(current))

    def __repr__(self) -> str:
        return f"<VPS id={self.id} label={self.label} host={self.host}>"


# ── Accounts ────────────────────────────────────────────────────────
class Account(Base):
    """A VPN account created on a VPS."""
    __tablename__ = "accounts"
    __table_args__ = (
        UniqueConstraint("vps_id", "protocol", "username", name="uq_account_vps_proto_user"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    vps_id: Mapped[int] = mapped_column(ForeignKey("vps.id"), index=True)
    protocol: Mapped[Protocol] = mapped_column(SAEnum(Protocol, native_enum=False))
    username: Mapped[str] = mapped_column(String(64))

    # Protocol-specific — only relevant fields will be set
    password: Mapped[Optional[str]] = mapped_column(String(128))
    uuid: Mapped[Optional[str]] = mapped_column(String(64))
    ip_limit: Mapped[int] = mapped_column(Integer, default=2)
    quota_gb: Mapped[int] = mapped_column(Integer, default=0, doc="0 = unlimited")

    # Config output (JSON string of connection details)
    config_json: Mapped[Optional[str]] = mapped_column(Text)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_trial: Mapped[bool] = mapped_column(Boolean, default=False)

    vps: Mapped[VPS] = relationship(back_populates="accounts")

    def __repr__(self) -> str:
        return (
            f"<Account id={self.id} proto={self.protocol.value} "
            f"user={self.username} exp={self.expires_at:%Y-%m-%d}>"
        )


# ── Payment / Orders ────────────────────────────────────────────────
class Order(Base):
    """A top-up order paid via Pakasir."""
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_ref: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    amount: Mapped[int] = mapped_column(Integer, doc="Amount in Rupiah")
    payment_method: Mapped[str] = mapped_column(String(32))
    status: Mapped[OrderStatus] = mapped_column(
        SAEnum(OrderStatus, native_enum=False), default=OrderStatus.PENDING
    )
    payment_url: Mapped[Optional[str]] = mapped_column(Text)
    payment_number: Mapped[Optional[str]] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    expired_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(back_populates="orders")

    def __repr__(self) -> str:
        return f"<Order ref={self.order_ref} amount={self.amount} status={self.status.value}>"


# ── Products / Plans ────────────────────────────────────────────────
class Product(Base):
    """Sellable plan (per protocol, per duration)."""
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128))
    protocol: Mapped[Protocol] = mapped_column(SAEnum(Protocol, native_enum=False))
    duration_days: Mapped[int] = mapped_column(Integer, default=30)
    price: Mapped[int] = mapped_column(Integer, doc="Price in Rupiah")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)

    def __repr__(self) -> str:
        return f"<Product {self.name} {self.duration_days}d Rp{self.price}>"

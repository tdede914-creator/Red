"""Balance manipulation with clear failure modes."""
from __future__ import annotations

import logging
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import User

log = logging.getLogger(__name__)


class InsufficientBalance(Exception):
    """Raised when a user tries to spend more than they have."""

    def __init__(self, current: int, needed: int):
        self.current = current
        self.needed = needed
        super().__init__(
            f"Saldo tidak cukup. Butuh Rp {needed:,}, saldo saat ini Rp {current:,}"
        )


async def deduct(session: AsyncSession, user_id: int, amount: int, memo: str = "") -> int:
    """Deduct amount from user's balance. Returns new balance.

    Raises InsufficientBalance if the deduction would go negative.
    Assumes caller manages the session/transaction.
    """
    if amount <= 0:
        raise ValueError("amount must be positive")

    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one()
    if user.balance < amount:
        raise InsufficientBalance(current=user.balance, needed=amount)

    user.balance -= amount
    log.info(
        "Balance deducted: user=%s -Rp%s → Rp%s (%s)",
        user_id, f"{amount:,}", f"{user.balance:,}", memo or "-",
    )
    return user.balance


async def refund(session: AsyncSession, user_id: int, amount: int, memo: str = "") -> int:
    """Add amount back to user's balance. Returns new balance."""
    if amount <= 0:
        raise ValueError("amount must be positive")

    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one()
    user.balance += amount
    log.info(
        "Balance refunded: user=%s +Rp%s → Rp%s (%s)",
        user_id, f"{amount:,}", f"{user.balance:,}", memo or "-",
    )
    return user.balance


async def get_balance(session: AsyncSession, user_id: int) -> int:
    result = await session.execute(select(User.balance).where(User.id == user_id))
    row = result.first()
    return int(row[0]) if row else 0

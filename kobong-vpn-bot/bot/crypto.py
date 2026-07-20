"""Symmetric encryption for storing VPS credentials at rest.

Uses Fernet (AES-128-CBC + HMAC-SHA256) from the `cryptography` library.
The key MUST be provided via `FERNET_KEY` env var and MUST NOT change once
you have encrypted data in the DB, otherwise decryption will fail.
"""
from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken

from .config import settings


class CryptoError(Exception):
    """Raised when encryption/decryption fails."""


_fernet = Fernet(settings.fernet_key.encode())


def encrypt(plaintext: str) -> str:
    """Encrypt a UTF-8 string, return URL-safe base64 ciphertext."""
    if not isinstance(plaintext, str):
        raise TypeError("encrypt() expects a str")
    return _fernet.encrypt(plaintext.encode("utf-8")).decode("ascii")


def decrypt(ciphertext: str) -> str:
    """Decrypt ciphertext produced by `encrypt()`."""
    try:
        return _fernet.decrypt(ciphertext.encode("ascii")).decode("utf-8")
    except InvalidToken as e:
        raise CryptoError(
            "Decryption failed — FERNET_KEY may have changed or ciphertext is corrupted"
        ) from e


def rotate(old_key: str, new_key: str, ciphertext: str) -> str:
    """Re-encrypt ciphertext from old key to new key (for key rotation)."""
    old_f = Fernet(old_key.encode())
    new_f = Fernet(new_key.encode())
    try:
        plain = old_f.decrypt(ciphertext.encode("ascii"))
    except InvalidToken as e:
        raise CryptoError("Old key does not decrypt this ciphertext") from e
    return new_f.encrypt(plain).decode("ascii")

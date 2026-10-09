import base64
import os
from functools import lru_cache

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import get_settings


class DecryptionError(Exception):
    pass


class SecretBox:
    """AES-GCM для секретов пользователей (ключи ИИ).

    `context` привязывает шифротекст к владельцу: значение одного пользователя
    не расшифруется, если его переложить в запись другого.
    """

    _version = "v1"

    def __init__(self, key_b64: str) -> None:
        key = base64.urlsafe_b64decode(key_b64 + "=" * (-len(key_b64) % 4))
        if len(key) != 32:
            raise ValueError("ENCRYPTION_KEY must be 32 bytes encoded as base64")
        self._aead = AESGCM(key)

    def encrypt(self, plaintext: str, *, context: str) -> str:
        nonce = os.urandom(12)
        ciphertext = self._aead.encrypt(nonce, plaintext.encode(), context.encode())
        return f"{self._version}:{base64.urlsafe_b64encode(nonce + ciphertext).decode()}"

    def decrypt(self, token: str, *, context: str) -> str:
        version, _, payload = token.partition(":")
        if version != self._version:
            raise DecryptionError("unknown version")
        raw = base64.urlsafe_b64decode(payload)
        try:
            return self._aead.decrypt(raw[:12], raw[12:], context.encode()).decode()
        except InvalidTag as exc:
            raise DecryptionError("invalid ciphertext") from exc


@lru_cache
def get_secret_box() -> SecretBox:
    return SecretBox(get_settings().encryption_key)

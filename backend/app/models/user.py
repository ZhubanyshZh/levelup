import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class AuthProvider(StrEnum):
    GOOGLE = "google"
    APPLE = "apple"
    PHONE = "phone"
    DEVICE = "device"


class User(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "users"

    display_name: Mapped[str | None] = mapped_column(String(100))
    email: Mapped[str | None] = mapped_column(String(320))
    avatar_url: Mapped[str | None] = mapped_column(String(1024))
    locale: Mapped[str] = mapped_column(String(10), default="ru", server_default="ru")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC", server_default="UTC")
    currency: Mapped[str | None] = mapped_column(String(3))
    # Активный провайдер ИИ: openai | gemini. Ключи — в ai_credentials.
    ai_provider: Mapped[str | None] = mapped_column(String(20))


class AuthIdentity(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Способ входа. У одного пользователя их может быть несколько (устройство + Google)."""

    __tablename__ = "auth_identities"
    __table_args__ = (UniqueConstraint("provider", "subject"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[str] = mapped_column(String(20))
    # Google: `sub` из ID token. Устройство: SHA-256 секрета устройства.
    subject: Mapped[str] = mapped_column(String(255))
    email: Mapped[str | None] = mapped_column(String(320))
    last_login_at: Mapped[datetime | None]


class RefreshToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Refresh-токены хранятся только как хэш.

    Все токены одного входа образуют «семью» (family_id): при обмене старый отзывается,
    новый продолжает семью. Повторное использование отозванного токена отзывает всю семью.
    """

    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[uuid.UUID] = mapped_column(index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime]
    revoked_at: Mapped[datetime | None]
    revoked_reason: Mapped[str | None] = mapped_column(String(20))
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL")
    )
    device_name: Mapped[str | None] = mapped_column(String(100))

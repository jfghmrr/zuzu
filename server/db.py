import os, time, uuid
from sqlalchemy import (
    create_engine,
    String,
    Text,
    Float,
    Integer,
    Boolean,
    JSON,
    UniqueConstraint,
    Index,
    event,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def uid():
    return str(uuid.uuid4())


def now():
    return time.time()


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    created: Mapped[float] = mapped_column(Float, default=now)
    profile: Mapped[dict] = mapped_column(JSON, default=dict)
    handle: Mapped[str | None] = mapped_column(String(40), unique=True)


class Contact(Base):
    __tablename__ = "private_contacts"
    contact: Mapped[str] = mapped_column(String(254), primary_key=True)
    owner: Mapped[str] = mapped_column(String(36), index=True)


class Pet(Base):
    __tablename__ = "pets"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner: Mapped[str] = mapped_column(String(36), unique=True)
    handle: Mapped[str] = mapped_column(String(40), unique=True)
    data: Mapped[dict] = mapped_column(JSON)


class LoginSession(Base):
    __tablename__ = "sessions"
    digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    owner: Mapped[str] = mapped_column(String(36), index=True)
    device: Mapped[str] = mapped_column(String(80))
    expires: Mapped[float] = mapped_column(Float)


class Challenge(Base):
    __tablename__ = "otp_challenges"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    contact: Mapped[str] = mapped_column(String(254), index=True)
    digest: Mapped[str] = mapped_column(String(64))
    created: Mapped[float] = mapped_column(Float, default=now)
    expires: Mapped[float] = mapped_column(Float)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
    link_owner: Mapped[str | None] = mapped_column(String(36))


class Item(Base):
    __tablename__ = "items"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    kind: Mapped[str] = mapped_column(String(24))
    owner: Mapped[str] = mapped_column(String(36))
    target: Mapped[str | None] = mapped_column(String(36))
    created: Mapped[float] = mapped_column(Float, default=now)
    updated: Mapped[float] = mapped_column(Float, default=now)
    expires: Mapped[float | None] = mapped_column(Float)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    data: Mapped[dict] = mapped_column(JSON)
    __table_args__ = (
        Index("items_feed", "kind", "created", "id"),
        Index("items_owner", "owner", "kind", "created"),
        Index("items_target", "target", "kind", "created"),
    )


class Edge(Base):
    __tablename__ = "relationships"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String(20))
    source: Mapped[str] = mapped_column(String(36))
    target: Mapped[str] = mapped_column(String(36))
    status: Mapped[str] = mapped_column(String(20), default="active")
    created: Mapped[float] = mapped_column(Float, default=now)
    __table_args__ = (
        UniqueConstraint("kind", "source", "target"),
        Index("edge_target", "kind", "target", "status"),
    )


class Media(Base):
    __tablename__ = "media"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner: Mapped[str] = mapped_column(String(36), index=True)
    scope: Mapped[str] = mapped_column(String(16))
    created: Mapped[float] = mapped_column(Float, default=now)
    resource: Mapped[str | None] = mapped_column(String(36), index=True)


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    owner: Mapped[str] = mapped_column(String(36), index=True)
    token: Mapped[str | None] = mapped_column(Text)


class Setting(Base):
    __tablename__ = "settings"
    owner: Mapped[str] = mapped_column(String(36), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)


class Rate(Base):
    __tablename__ = "rate_limits"
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
    until: Mapped[float] = mapped_column(Float)


class Audit(Base):
    __tablename__ = "moderation_audit"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    target: Mapped[str] = mapped_column(String(36))
    action: Mapped[str] = mapped_column(String(32))
    created: Mapped[float] = mapped_column(Float, default=now)
    reason: Mapped[str] = mapped_column(Text)


class Outbox(Base):
    __tablename__ = "push_outbox"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner: Mapped[str] = mapped_column(String(36), index=True)
    data: Mapped[dict] = mapped_column(JSON)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    delivered: Mapped[bool] = mapped_column(Boolean, default=False)
    created: Mapped[float] = mapped_column(Float, default=now)


url = os.getenv("DATABASE_URL", "sqlite:///./zuzu.db")
engine = create_engine(
    url,
    connect_args={"check_same_thread": False} if url.startswith("sqlite") else {},
    pool_pre_ping=True,
)
if url.startswith("sqlite"):

    @event.listens_for(engine, "connect")
    def setup(conn, _):
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")


Session = sessionmaker(engine, expire_on_commit=False)

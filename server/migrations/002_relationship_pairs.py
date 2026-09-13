"""Prevent simultaneous reverse requests; portable SQLite/PostgreSQL index."""

from sqlalchemy import text
from db import engine


def migrate():
    with engine.begin() as c:
        c.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS edge_unordered_pair ON relationships (kind, CASE WHEN source < target THEN source ELSE target END, CASE WHEN source < target THEN target ELSE source END) WHERE kind IN ('friend','conversation')"
            )
        )
        c.execute(
            text(
                "INSERT INTO schema_version(version) VALUES(2) ON CONFLICT(version) DO NOTHING"
            )
        )


if __name__ == "__main__":
    migrate()

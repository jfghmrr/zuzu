"""Version 1. Run `python -m migrations.001_initial` before server startup.
Initial schema is frozen by models at first release. Later schema changes must use
new numbered scripts, never silently alter an existing database.
"""

from db import Base, engine
from sqlalchemy import text


def migrate():
    with engine.begin() as conn:
        conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)"
            )
        )
        if not conn.execute(
            text("SELECT version FROM schema_version WHERE version=1")
        ).first():
            Base.metadata.create_all(conn)
            conn.execute(text("INSERT INTO schema_version(version) VALUES(1)"))


if __name__ == "__main__":
    migrate()

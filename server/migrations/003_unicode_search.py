from sqlalchemy import select, text
from db import Session, Pet


def migrate():
    with Session() as db:
        for p in db.scalars(select(Pet)).all():
            if "search_name" not in p.data:
                p.data = {**p.data, "search_name": p.data["name"].casefold()}
        db.execute(
            text(
                "INSERT INTO schema_version(version) VALUES(3) ON CONFLICT(version) DO NOTHING"
            )
        )
        db.commit()

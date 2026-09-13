"""Single worker: outbox delivery, due inbox reminders, retention cleanup.
Run with `python worker.py --once` or keep running. No device push for reminders.
"""

import os, time, uuid
import httpx
from datetime import datetime, timezone
from sqlalchemy import select, delete
from db import (
    Session,
    Item,
    Media,
    Device,
    Outbox,
    Setting,
    Rate,
    Challenge,
    LoginSession,
    now,
)
from app import STORE, blocked_ids


def tick():
    with Session() as db:
        for r in db.scalars(select(Item).where(Item.kind == "reminders")).all():
            d = r.data
            if d.get("done") or datetime.fromisoformat(d["due_at"]).timestamp() > now():
                continue
            iid = str(
                uuid.uuid5(uuid.NAMESPACE_URL, f"zuzu:reminder:{r.id}:{r.updated}")
            )
            if not db.get(Item, iid):
                db.add(
                    Item(
                        id=iid,
                        kind="notifications",
                        owner=r.owner,
                        target=r.id,
                        data={"title": d["title"], "route": "reminder", "read": False},
                    )
                )
        db.execute(delete(Rate).where(Rate.until < now()))
        db.execute(delete(Challenge).where(Challenge.expires < now() - 86400))
        db.execute(delete(LoginSession).where(LoginSession.expires < now()))
        for m in db.scalars(
            select(Media).where(Media.resource == None, Media.created < now() - 86400)
        ).all():
            (STORE / (m.id + ".jpg")).unlink(missing_ok=True)
            db.delete(m)
        # Expired stories lose server access immediately; remove files after 24h grace.
        for i in db.scalars(
            select(Item).where(Item.kind == "stories", Item.expires < now() - 86400)
        ).all():
            for m in db.scalars(select(Media).where(Media.resource == i.id)).all():
                (STORE / (m.id + ".jpg")).unlink(missing_ok=True)
                db.delete(m)
        db.commit()
        known = set(db.scalars(select(Media.id)).all())
        for file in STORE.glob("*.jpg"):
            if file.stem not in known and file.stat().st_mtime < now() - 86400:
                file.unlink(missing_ok=True)
    url = os.getenv("PUSH_WEBHOOK_URL")
    if not url:
        return
    with Session() as db:
        for event in db.scalars(
            select(Outbox)
            .where(Outbox.delivered == False, Outbox.attempts < 8)
            .order_by(Outbox.created)
            .limit(50)
        ).all():
            settings = db.get(Setting, event.owner)
            if (
                settings
                and settings.data.get("push") == False
                or event.data.get("sender") in blocked_ids(db, event.owner)
            ):
                event.delivered = True
                continue
            devices = db.scalars(
                select(Device).where(Device.owner == event.owner)
            ).all()
            if not devices:
                event.delivered = True
                continue
            event.attempts += 1
            try:
                # Provider bridge must deduplicate by event id; retry can follow an ambiguous timeout.
                response = httpx.post(
                    url,
                    json={
                        "id": event.id,
                        "tokens": [d.token for d in devices if d.token],
                        "notification": {
                            "title": event.data["title"],
                            "body": "Откройте ЗуЗу",
                        },
                        "data": {
                            "route": event.data["route"],
                            "target": event.data["target"],
                        },
                    },
                    headers={
                        "Authorization": "Bearer " + os.getenv("PUSH_WEBHOOK_TOKEN", "")
                    },
                    timeout=10,
                )
                response.raise_for_status()
                event.delivered = True
            except httpx.HTTPError:
                pass
        db.commit()


if __name__ == "__main__":
    import sys, importlib

    importlib.import_module("migrations.001_initial").migrate()
    while True:
        tick()
        if "--once" in sys.argv:
            break
        time.sleep(30)

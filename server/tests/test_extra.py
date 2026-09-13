import uuid, concurrent.futures
from sqlalchemy import delete, select, update
from test_api import client, login, pet, post, photo
from db import Session, Base, Challenge, Item, Contact, Edge, now
from app import app
from fastapi.testclient import TestClient
from datetime import datetime, timezone


def reset_rates():
    from db import Rate

    with Session() as db:
        db.execute(delete(Rate))
        db.commit()


def test_contact_linking_and_replay(client):
    reset_rates()
    c = client
    a, aid = login(c)
    b, bid = login(c)
    contact = f"link-{uuid.uuid4()}@example.test"
    ch = c.post(
        "/auth/request", headers=a, json={"contact": contact, "link": True}
    ).json()
    assert (
        c.post(
            "/auth/verify",
            headers=b,
            json={"challenge_id": ch["challenge_id"], "code": ch["dev_code"]},
        ).status_code
        == 403
    )
    assert c.post(
        "/auth/verify",
        headers=a,
        json={"challenge_id": ch["challenge_id"], "code": ch["dev_code"]},
    ).json()["linked"]
    assert (
        c.post(
            "/auth/verify",
            headers=a,
            json={"challenge_id": ch["challenge_id"], "code": ch["dev_code"]},
        ).status_code
        == 400
    )
    with Session() as db:
        assert db.get(Contact, contact).owner == aid
        db.execute(
            update(Challenge)
            .where(Challenge.id == ch["challenge_id"])
            .values(created=now() - 61)
        )
        db.commit()
    ch = c.post("/auth/request", json={"contact": contact}).json()
    r = c.post(
        "/auth/verify",
        json={
            "challenge_id": ch["challenge_id"],
            "code": ch["dev_code"],
            "device": "second-device",
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["account_id"] == aid


def test_friend_reverse_constraint_and_cancel(client):
    reset_rates()
    c = client
    a, aid = login(c)
    b, bid = login(c)
    for h, other in ((a, bid), (b, aid)):
        assert (
            c.put(
                f"/relationships/{other}/friend",
                headers=h,
                json={"operation": "request"},
            ).status_code
            == 200
        )
    with Session() as db:
        assert (
            len(
                db.scalars(
                    select(Edge).where(
                        Edge.kind == "friend",
                        Edge.source.in_([aid, bid]),
                        Edge.target.in_([aid, bid]),
                    )
                ).all()
            )
            == 1
        )
    assert (
        c.put(
            f"/relationships/{aid}/friend", headers=b, json={"operation": "cancel"}
        ).status_code
        == 403
    )
    assert (
        c.put(
            f"/relationships/{bid}/friend", headers=a, json={"operation": "cancel"}
        ).status_code
        == 200
    )
    assert not c.get("/items/notifications", headers=b).json()["items"]


def test_keyset_pagination_and_hidden_parent(client):
    reset_rates()
    c = client
    a, aid = login(c)
    b, bid = login(c)
    pet(c, a)
    for n in range(5):
        assert post(c, a, "posts", {"text": str(n)}).status_code == 200
    page = c.get("/items/posts?limit=2", headers=a).json()
    ids = [i["id"] for i in page["items"]]
    while page["next"]:
        params = page["next"]
        params["limit"] = 2
        page = c.get("/items/posts", params=params, headers=a).json()
        ids.extend(i["id"] for i in page["items"])
    assert len(ids) == 5 and len(set(ids)) == 5
    comment = post(c, b, "comments", {"text": "comment"}, ids[0]).json()
    c.post(
        "/admin/moderate",
        headers={"X-Admin-Key": "test-moderator-key"},
        json={"target": ids[0], "action": "hide", "reason": "Test"},
    )
    assert c.get("/item/" + comment["id"], headers=b).status_code == 404


def test_worker_inbox_reminder_once_and_reschedule(client):
    reset_rates()
    c = client
    a, aid = login(c)
    pet(c, a)
    from worker import tick

    r = post(
        c,
        a,
        "reminders",
        {
            "title": "Test",
            "due_at": "2020-01-01T10:00:00+03:00",
            "timezone": "Europe/Moscow",
            "done": False,
        },
    ).json()
    tick()
    tick()
    assert len(c.get("/items/notifications", headers=a).json()["items"]) == 1
    d = {**r["data"], "done": True}
    assert c.put("/item/" + r["id"], headers=a, json={"data": d}).status_code == 200
    tick()
    assert len(c.get("/items/notifications", headers=a).json()["items"]) == 0


def test_logout_revokes_only_current_session(client):
    reset_rates()
    c = client
    a, aid = login(c)
    assert c.put("/devices", headers=a, json={"token": "test-token"}).status_code == 200
    assert c.post("/auth/logout", headers=a).status_code == 200
    assert c.get("/me", headers=a).status_code == 401
    from db import Device

    with Session() as db:
        assert not db.scalar(select(Device).where(Device.owner == aid))


def test_unicode_search_and_moderator_map(client):
    reset_rates()
    c = client
    a, aid = login(c)
    pet(c, a)
    assert any(
        p["id"] == aid for p in c.get("/profiles?q=лУнА", headers=a).json()["items"]
    )
    payload = {
        "id": str(uuid.uuid4()),
        "source": "Проверено вручную в тесте",
        "data": {
            "title": "Тестовый объект",
            "city": "Тест",
            "lat": 0,
            "lng": 0,
            "category": "factory",
        },
    }
    assert c.post("/admin/map", headers=a, json=payload).status_code == 403
    assert (
        c.post(
            "/admin/map", headers={"X-Admin-Key": "test-moderator-key"}, json=payload
        ).status_code
        == 200
    )
    assert post(c, a, "markers", payload["data"]).status_code == 422


def test_feed_comment_counts_respect_blocking_and_deletion(client):
    reset_rates()
    c = client
    a, aid = login(c)
    b, bid = login(c)
    pet(c, a)
    pet(c, b)
    avatar = photo(c, a, 'public')
    assert c.put('/me/profile', headers=a, json={'name': 'Арина', 'status': 'Заботливый хозяин', 'handle': 'o_' + uuid.uuid4().hex[:10], 'photo': avatar}).status_code == 200
    publication = post(c, a, 'posts', {'text': 'Запись'}).json()
    comment = post(c, b, 'comments', {'text': 'Ответ'}, target=publication['id']).json()
    feed = c.get('/item/' + publication['id'], headers=a).json()
    assert feed['owner_avatar'] == avatar
    assert feed['comments'] == 1
    assert c.put(f'/relationships/{bid}/block', headers=a, json={'active': True}).status_code == 200
    assert c.get('/item/' + publication['id'], headers=a).json()['comments'] == 0
    assert c.put(f'/relationships/{bid}/block', headers=a, json={'active': False}).status_code == 200
    assert c.delete('/item/' + comment['id'], headers=b).status_code == 200
    assert c.get('/item/' + publication['id'], headers=a).json()['comments'] == 0

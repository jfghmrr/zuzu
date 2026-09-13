import os, sys, tempfile, uuid, io, time
from pathlib import Path

os.environ["DATABASE_URL"] = "sqlite:///" + tempfile.mktemp(suffix=".db")
os.environ["MEDIA_DIR"] = tempfile.mkdtemp()
os.environ["AUTH_MODE"] = "dev"
os.environ["ADMIN_KEY"] = "test-moderator-key"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select, update
from app import app, months_between
from db import Session, Challenge, Item, Media, LoginSession, now
from datetime import date


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def login(c):
    contact = f"{uuid.uuid4()}@example.test"
    r = c.post("/auth/request", json={"contact": contact})
    assert r.status_code == 200, r.text
    ch = r.json()
    r = c.post(
        "/auth/verify",
        json={
            "challenge_id": ch["challenge_id"],
            "code": ch["dev_code"],
            "device": str(uuid.uuid4()),
            "privacy": "draft-local",
            "terms": "draft-local",
        },
    )
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}, r.json()["account_id"]


def pet(c, h):
    r = c.post(
        "/pets",
        headers=h,
        json={
            "name": "Луна",
            "species": "Игуана",
            "city": "Москва",
            "handle": "p_" + uuid.uuid4().hex[:10],
            "approx_months": 12,
        },
    )
    assert r.status_code == 200, r.text


def post(c, h, kind, d, target=None, iid=None):
    return c.post(
        "/items/" + kind,
        headers=h,
        json={"id": iid or str(uuid.uuid4()), "data": d, "target": target},
    )


def photo(c, h, scope):
    b = io.BytesIO()
    Image.new("RGB", (32, 32), "yellow").save(b, "PNG")
    r = c.post(
        "/media?scope=" + scope,
        headers=h,
        files={"file": ("doc.png", b.getvalue(), "image/png")},
    )
    assert r.status_code == 200, r.text
    return r.json()["id"]


def test_auth_attempts_expiry_and_replay(client):
    c = client
    r = c.post("/auth/request", json={"contact": "otp@example.test"})
    ch = r.json()
    assert (
        c.post("/auth/request", json={"contact": "otp@example.test"}).status_code == 429
    )
    bad = {"challenge_id": ch["challenge_id"], "code": "bad", "device": "x"}
    for _ in range(5):
        assert c.post("/auth/verify", json=bad).status_code == 400
    assert (
        c.post("/auth/verify", json={**bad, "code": ch["dev_code"]}).status_code == 429
    )
    r = c.post("/auth/request", json={"contact": "expired@example.test"})
    ch = r.json()
    with Session() as db:
        db.execute(
            update(Challenge)
            .where(Challenge.id == ch["challenge_id"])
            .values(expires=now() - 1)
        )
        db.commit()
    assert (
        c.post(
            "/auth/verify", json={**bad, "challenge_id": ch["challenge_id"]}
        ).status_code
        == 400
    )
    assert c.get("/me").status_code == 401


def test_single_pet_and_profile_ownership(client):
    c = client
    a, aid = login(c)
    b, bid = login(c)
    pet(c, a)
    assert c.post("/pets", headers=a, json={}).status_code == 409
    assert (
        c.put(
            "/me/profile",
            headers=b,
            json={"name": "B", "status": "Эксперт", "handle": "owner_b", "id": aid},
        ).status_code
        == 422
    )
    assert c.get("/me", headers=a).json()["pet"]["species"] == "Игуана"


def test_private_vet_media_and_lifecycle(client):
    c = client
    a, aid = login(c)
    b, bid = login(c)
    pet(c, a)
    m = photo(c, a, "vet")
    r = post(
        c,
        a,
        "vet",
        {
            "title": "Осмотр",
            "visit_date": "2026-09-13",
            "diagnosis": "Со слов владельца",
            "recommendations": "Запись",
            "media": [m],
        },
    )
    assert r.status_code == 200, r.text
    vid = r.json()["id"]
    assert c.get("/media/" + m, headers=a).status_code == 200
    assert c.get("/media/" + m, headers=b).status_code == 404
    assert c.get("/item/" + vid, headers=b).status_code == 404
    assert c.get("/items/vet", headers=b).json()["items"] == []
    assert c.put("/item/" + vid, headers=b, json={"data": {}}).status_code == 404
    r = post(
        c,
        a,
        "reminders",
        {
            "title": "Контроль",
            "due_at": "2026-10-03T09:30:00+03:00",
            "timezone": "Europe/Moscow",
            "vet_id": vid,
            "done": False,
            "tasks": [{"title": "Взять паспорт", "done": False}],
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["data"]["due_at"] == "2026-10-03T06:30:00+00:00"
    assert c.delete("/item/" + vid, headers=a).status_code == 200
    assert c.get("/media/" + m, headers=b).status_code == 404


def test_posts_comments_reactions_idempotency(client):
    c = client
    a, aid = login(c)
    b, bid = login(c)
    pet(c, a)
    pet(c, b)
    media = [photo(c, a, "public"), photo(c, a, "public")]
    iid = str(uuid.uuid4())
    r = post(c, a, "posts", {"text": "Привет", "media": media}, iid=iid)
    assert r.status_code == 200, r.text
    assert (
        post(c, a, "posts", {"text": "Привет", "media": media}, iid=iid).json()["id"]
        == iid
    )
    assert len(c.get("/items/posts", headers=a).json()["items"]) == 1
    assert c.get("/items/posts", headers=b).json()["items"] == []
    assert (
        c.put(
            "/relationships/" + aid + "/follow", headers=b, json={"active": True}
        ).status_code
        == 200
    )
    assert len(c.get("/items/posts", headers=b).json()["items"]) == 1
    for _ in range(2):
        r = c.put("/item/" + iid + "/like", headers=b, json={"active": True})
    assert r.json()["likes"] == 1
    com = post(c, b, "comments", {"text": "Красавица"}, iid).json()
    reply = post(c, a, "comments", {"text": "Спасибо", "parent_id": com["id"]}, iid)
    assert reply.status_code == 200
    report = post(c, a, "reports", {"reason": "Спам", "text": "Проверить"}, com["id"])
    assert report.status_code == 200
    assert c.get("/admin/queue").status_code == 403
    assert (
        c.get("/admin/queue", headers={"X-Admin-Key": "test-moderator-key"}).status_code
        == 200
    )
    assert c.delete("/item/" + iid, headers=b).status_code == 403
    assert c.delete("/item/" + iid, headers=a).status_code == 200
    assert c.get("/item/" + com["id"], headers=b).status_code == 404
    assert c.get("/media/" + media[0], headers=b).status_code == 404


def test_friendship_chat_story_and_block(client):
    c = client
    a, aid = login(c)
    b, bid = login(c)
    outsider, oid = login(c)
    pet(c, a)
    pet(c, b)
    assert (
        c.put(
            f"/relationships/{bid}/friend", headers=a, json={"operation": "request"}
        ).status_code
        == 200
    )
    assert (
        c.put(
            f"/relationships/{bid}/friend", headers=a, json={"operation": "accept"}
        ).status_code
        == 409
    )
    assert (
        c.put(
            f"/relationships/{aid}/friend", headers=b, json={"operation": "accept"}
        ).status_code
        == 200
    )
    assert c.get("/me", headers=a).json()["friends"] == 1
    cid = c.post("/conversations", headers=a, json={"account_id": bid}).json()["id"]
    assert (
        c.post("/conversations", headers=b, json={"account_id": aid}).json()["id"]
        == cid
    )
    assert c.get("/items/messages?target=" + cid, headers=outsider).status_code == 404
    sm = photo(c, a, "public")
    st = post(c, a, "stories", {"text": "День", "media": [sm]}).json()
    sid = st["id"]
    assert c.post("/stories/" + sid + "/view", headers=b).status_code == 200
    assert c.get("/stories/" + sid + "/views", headers=b).status_code == 403
    assert len(c.get("/stories/" + sid + "/views", headers=a).json()["items"]) == 1
    mid = str(uuid.uuid4())
    d = {"text": "Привет!", "story_id": sid}
    assert post(c, b, "messages", d, cid, mid).status_code == 200
    assert post(c, b, "messages", d, cid, mid).json()["id"] == mid
    assert c.get("/conversations", headers=a).json()["items"][0]["unread"] == 1
    assert (
        c.post(
            "/conversations/" + cid + "/read", headers=a, json={"message_id": mid}
        ).status_code
        == 200
    )
    assert c.get("/item/" + mid, headers=b).json()["read"]
    with Session() as db:
        db.execute(update(Item).where(Item.id == sid).values(expires=now() - 1))
        db.commit()
    assert c.get("/item/" + sid, headers=b).status_code == 404
    assert c.get("/media/" + sm, headers=b).status_code == 404
    assert c.get("/item/" + mid, headers=b).json()["story_available"] == False
    assert (
        c.put(
            f"/relationships/{bid}/block", headers=a, json={"active": True}
        ).status_code
        == 200
    )
    assert post(c, b, "messages", {"text": "Обход"}, cid).status_code == 404
    assert c.get("/profiles/" + aid, headers=b).status_code == 404
    assert c.get("/me", headers=a).json()["friends"] == 0
    assert (
        c.put(
            f"/relationships/{bid}/block", headers=a, json={"active": False}
        ).status_code
        == 200
    )
    assert post(c, b, "messages", {"text": "Снова"}, cid).status_code == 200


def test_map_bounds_and_moderation(client):
    c = client
    a, aid = login(c)
    b, bid = login(c)
    m = post(
        c,
        a,
        "markers",
        {
            "title": "Сообщение",
            "text": "Не подтверждено",
            "city": "Москва",
            "lat": 55.75,
            "lng": 37.6,
            "category": "danger",
        },
    )
    assert m.status_code == 200, m.text
    iid = m.json()["id"]
    assert (
        len(
            c.get("/items/markers?west=37&south=55&east=38&north=56", headers=b).json()[
                "items"
            ]
        )
        == 1
    )
    assert (
        c.get("/items/markers?west=0&south=0&east=1&north=1", headers=b).json()["items"]
        == []
    )
    assert post(c, b, "map_messages", {"text": "Спасибо"}, iid).status_code == 200
    assert (
        c.post(
            "/admin/moderate",
            headers={"X-Admin-Key": "test-moderator-key"},
            json={"target": iid, "action": "hide", "reason": "Проверка"},
        ).status_code
        == 200
    )
    assert c.get("/item/" + iid, headers=b).status_code == 404
    assert c.get("/items/markers", headers=b).json()["items"] == []


def test_validation_and_account_deletion(client):
    c = client
    a, aid = login(c)
    pet(c, a)
    assert post(c, a, "posts", {"text": "x" * 5001}).status_code == 422
    assert (
        post(
            c,
            a,
            "reminders",
            {"title": "x", "due_at": "2026-01-01T10:00:00", "timezone": "bad"},
        ).status_code
        == 422
    )
    assert (
        c.post(
            "/media",
            headers=a,
            files={"file": ("evil.jpg", b"not an image", "image/jpeg")},
        ).status_code
        == 422
    )
    m = photo(c, a, "vet")
    assert post(c, a, "posts", {"media": [m]}).status_code == 403
    assert (
        c.request(
            "DELETE", "/me", headers=a, json={"confirmation": "УДАЛИТЬ"}
        ).status_code
        == 200
    )
    assert c.get("/me", headers=a).status_code == 401
    with Session() as db:
        assert not db.get(Media, m)


def test_calendar_month_boundaries():
    assert months_between(date(2024, 9, 13), date(2026, 9, 12)) == 23
    assert months_between(date(2024, 9, 13), date(2026, 9, 13)) == 24
    assert months_between(date(2026, 8, 31), date(2026, 9, 1)) == 0

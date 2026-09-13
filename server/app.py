"""Zuzu API. All authorization is enforced here; clients never access the DB."""

import os, re, io, json, hashlib, secrets, uuid, importlib, warnings
from datetime import datetime, date, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from pathlib import Path
from contextlib import asynccontextmanager
import httpx
from PIL import Image, ImageOps, UnidentifiedImageError
from fastapi import FastAPI, Depends, Header, HTTPException, UploadFile, File, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from sqlalchemy import select, or_, and_, delete, update, func
from sqlalchemy.exc import IntegrityError
from db import *

DEV = os.getenv("AUTH_MODE", "webhook") == "dev"
ENV = os.getenv("APP_ENV", "development")
MAX_PHOTOS = 8
MAX_BYTES = 10 * 1024 * 1024
MAX_TEXT = 5000
STORE = Path(os.getenv("MEDIA_DIR", "./private_media"))
STORE.mkdir(parents=True, exist_ok=True)
LEGAL_VERSION = os.getenv("LEGAL_VERSION", "draft-local")
PRIVATE = {"vet", "reminders", "notifications", "feedback", "reports", "consents"}
KINDS = {
    "posts",
    "comments",
    "stories",
    "messages",
    "vet",
    "reminders",
    "markers",
    "news",
    "map_messages",
    "feedback",
    "reports",
    "notifications",
    "consents",
}


def fail(code, message):
    raise HTTPException(code, message)


def digest(s):
    return hashlib.sha256(s.encode()).hexdigest()


def valid_id(v):
    try:
        return str(uuid.UUID(str(v)))
    except (ValueError, TypeError, AttributeError):
        fail(422, "Некорректный идентификатор.")


def text_value(d, key, maximum=MAX_TEXT, required=False):
    v = d.get(key, "")
    if not isinstance(v, str) or len(v) > maximum or (required and not v.strip()):
        fail(422, f"Проверьте поле «{key}» (до {maximum} символов).")
    return v.strip()


def contact_value(s):
    s = str(s).strip().lower()
    if re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", s) and len(s) <= 254:
        return s
    s = re.sub(r"[\s()\-]", "", s)
    if re.fullmatch(r"\+[1-9]\d{7,14}", s):
        return s
    fail(
        422, "Введите email или телефон в международном формате, например +79991234567."
    )


def db_session():
    with Session() as db:
        try:
            yield db
        except:
            db.rollback()
            raise


def auth(authorization: str = Header(default=""), db=Depends(db_session)):
    token = authorization.removeprefix("Bearer ")
    s = db.get(LoginSession, digest(token))
    if not s or s.expires < now() or not db.get(Account, s.owner):
        fail(401, "Войдите в аккаунт заново.")
    return s


def blocked_ids(db, me):
    rows = db.scalars(
        select(Edge).where(
            Edge.kind == "block", or_(Edge.source == me, Edge.target == me)
        )
    ).all()
    return [r.target if r.source == me else r.source for r in rows]


def allowed_user(db, me, other):
    if not db.get(Account, other) or other in blocked_ids(db, me):
        fail(404, "Профиль недоступен.")


def rate(db, key, limit=60, seconds=60):
    # Dedicated committed transaction: failed validations cannot erase rate counters.
    bucket = f"{key}:{int(now() // seconds)}"
    with Session() as rd:
        try:
            rd.add(Rate(key=bucket, count=0, until=now() + seconds * 2))
            rd.commit()
        except IntegrityError:
            rd.rollback()
        ok = rd.execute(
            update(Rate)
            .where(Rate.key == bucket, Rate.count < limit)
            .values(count=Rate.count + 1)
        ).rowcount
        rd.commit()
    if not ok:
        fail(429, "Слишком много запросов. Подождите и повторите.")


def conversation(db, me, cid):
    e = db.get(Edge, cid)
    if not e or e.kind != "conversation" or me not in (e.source, e.target):
        fail(404, "Диалог недоступен.")
    allowed_user(db, me, e.target if e.source == me else e.source)
    return e


def readable(db, me, item):
    if not item or item.hidden or (item.expires and item.expires <= now()):
        fail(404, "Запись удалена или больше недоступна.")
    if item.kind in PRIVATE:
        if item.owner != me:
            fail(404, "Запись недоступна.")
    elif item.kind == "messages":
        conversation(db, me, item.target)
    else:
        allowed_user(db, me, item.owner)
        if item.kind in ("comments", "map_messages"):
            readable(db, me, db.get(Item, item.target))
    return item


def pet_for(db, owner):
    return db.scalar(select(Pet).where(Pet.owner == owner))


def months_between(a, b):
    return (b.year - a.year) * 12 + b.month - a.month - (b.day < a.day)


def profile_json(db, a, me):
    p = pet_for(db, a.id)
    months = months_between(
        datetime.fromtimestamp(a.created, timezone.utc).date(),
        datetime.now(timezone.utc).date(),
    )
    level = next(
        label
        for boundary, label in [
            (1, "Новый друг"),
            (3, "Свой человек"),
            (6, "Опытный хозяин"),
            (24, "Авторитет"),
            (10**9, "Легенда"),
        ]
        if months < boundary
    )
    count = lambda *where: db.scalar(
        select(func.count()).select_from(Edge).where(*where)
    )
    pet = (
        {
            **{k: v for k, v in p.data.items() if k != "search_name"},
            "id": p.id,
            "handle": p.handle,
        }
        if p
        else None
    )
    if pet:
        if pet.get("birth_date"):
            pet["age_months"] = max(
                0,
                months_between(
                    date.fromisoformat(pet["birth_date"]),
                    datetime.now(timezone.utc).date(),
                ),
            )
        elif pet.get("approx_months") is not None:
            pet["age_months"] = int(pet["approx_months"]) + max(
                0,
                months_between(
                    date.fromisoformat(pet["age_as_of"]),
                    datetime.now(timezone.utc).date(),
                ),
            )
    return {
        "id": a.id,
        "created": a.created,
        "handle": a.handle,
        "owner": a.profile,
        "pet": pet,
        "level": level,
        "achievements": db.scalar(
            select(func.count())
            .select_from(Item)
            .where(
                Item.owner == a.id,
                Item.kind.in_(["posts", "markers"]),
                Item.hidden == False,
            )
        ),
        "followers": count(Edge.kind == "follow", Edge.target == a.id),
        "friends": count(
            Edge.kind == "friend",
            Edge.status == "accepted",
            or_(Edge.source == a.id, Edge.target == a.id),
        ),
        "following": bool(
            count(Edge.kind == "follow", Edge.source == me, Edge.target == a.id)
        ),
    }


def item_json(db, i, me):
    a = db.get(Account, i.owner)
    p = pet_for(db, i.owner)
    reactions = db.scalars(
        select(Edge).where(
            Edge.kind == "like",
            Edge.target == i.id,
            Edge.source.not_in(blocked_ids(db, me)),
        )
    ).all()
    d = {
        "id": i.id,
        "kind": i.kind,
        "owner_id": i.owner,
        "target": i.target,
        "created": i.created,
        "updated": i.updated,
        "expires": i.expires,
        "data": i.data,
        "author": p.data.get("name", "")
        if p
        else (a.profile.get("name", "") if a else "Удалённый аккаунт"),
        "avatar": p.data.get("photo") if p else None,
        "likes": len(reactions),
        "liked": any(r.source == me for r in reactions),
    }
    if i.kind == "messages":
        e = conversation(db, me, i.target)
        other = e.target if e.source == i.owner else e.source
        read = db.scalar(
            select(Edge).where(
                Edge.kind == "read", Edge.source == other, Edge.target == i.target
            )
        )
        d["read"] = bool(read and read.created >= i.created)
        if i.data.get("story_id"):
            s = db.get(Item, i.data["story_id"])
            d["story_available"] = bool(s and not s.hidden and s.expires > now())
    return d


def notification(db, owner, title, kind, target):
    db.add(
        Item(
            id=uid(),
            kind="notifications",
            owner=owner,
            target=target,
            data={"title": title, "route": kind, "read": False},
        )
    )


def validate_item(db, me, kind, d, existing=None):
    if not isinstance(d, dict):
        fail(422, "Некорректные данные.")
    # Unknown properties cannot smuggle ownership/status/administrative fields.
    fields = {
        "posts": {"text", "media"},
        "stories": {"text", "media"},
        "comments": {"text", "parent_id"},
        "messages": {"text", "media", "story_id"},
        "vet": {"title", "visit_date", "diagnosis", "recommendations", "media"},
        "reminders": {"title", "due_at", "timezone", "note", "done", "tasks", "vet_id"},
        "markers": {"title", "text", "lat", "lng", "category", "status", "city"},
        "news": {"title", "text", "lat", "lng", "city"},
        "map_messages": {"text"},
        "feedback": {"name", "email", "text"},
        "reports": {"reason", "text"},
        "notifications": {"read"},
    }
    if kind not in fields or set(d) - fields[kind]:
        fail(422, "Недопустимые поля записи.")
    d = dict(d)
    for k, v in d.items():
        if isinstance(v, str) and len(v) > MAX_TEXT:
            fail(422, "Слишком длинный текст.")
    if kind in ("posts", "stories", "messages"):
        text_value(d, "text", 2000 if kind == "messages" else MAX_TEXT)
        if not d.get("text", "").strip() and not d.get("media"):
            fail(422, "Добавьте текст или фотографию.")
        if kind == "stories" and len(d.get("media", [])) != 1:
            fail(422, "Для истории нужна одна фотография.")
    if kind in ("comments", "map_messages"):
        text_value(d, "text", 2000, True)
    if kind in ("vet", "reminders", "markers", "news"):
        text_value(d, "title", 120, True)
    if kind == "vet":
        try:
            date.fromisoformat(d["visit_date"])
        except (ValueError, KeyError, TypeError):
            fail(422, "Укажите дату посещения.")
    if kind == "reminders":
        try:
            dt = datetime.fromisoformat(d["due_at"].replace("Z", "+00:00"))
            if dt.tzinfo is None:
                raise ValueError()
            ZoneInfo(d["timezone"])
            d["due_at"] = dt.astimezone(timezone.utc).isoformat()
        except (ValueError, KeyError, TypeError, ZoneInfoNotFoundError):
            fail(422, "Укажите дату, время и часовой пояс.")
        if type(d.get("done", False)) is not bool:
            fail(422, "Некорректное состояние задачи.")
        tasks = d.get("tasks", [])
        if (
            not isinstance(tasks, list)
            or len(tasks) > 30
            or any(
                not isinstance(t, dict)
                or set(t) != {"title", "done"}
                or not isinstance(t["title"], str)
                or len(t["title"]) > 120
                or type(t["done"]) is not bool
                for t in tasks
            )
        ):
            fail(422, "Проверьте список задач.")
        if d.get("vet_id"):
            v = readable(db, me, db.get(Item, d["vet_id"]))
            if v.kind != "vet":
                fail(422, "Ветзапись недоступна.")
    if kind in ("markers", "news"):
        try:
            if not -90 <= float(d["lat"]) <= 90 or not -180 <= float(d["lng"]) <= 180:
                raise ValueError()
            d["lat"] = float(d["lat"])
            d["lng"] = float(d["lng"])
        except (ValueError, TypeError, KeyError):
            fail(422, "Выберите точку на карте.")
        text_value(d, "city", 120, True)
        if kind == "markers":
            if d.get("category") not in ("danger", "lost", "found", "other"):
                fail(422, "Выберите категорию происшествия.")
            if d.get("status", "active") not in ("active", "closed"):
                fail(422, "Некорректный статус.")
            d.setdefault("status", "active")
    if kind == "feedback":
        text_value(d, "name", 120, True)
        contact_value(d.get("email", ""))
        text_value(d, "text", 5000, True)
    if kind == "reports":
        if d.get("reason") not in ("Оскорбительный контент", "Дезинформация", "Спам"):
            fail(422, "Выберите причину жалобы.")
    if kind == "notifications" and (set(d) != {"read"} or type(d["read"]) is not bool):
        fail(422, "Некорректное состояние уведомления.")
    media = d.get("media", [])
    if (
        not isinstance(media, list)
        or len(media) > MAX_PHOTOS
        or len(set(map(str, media))) != len(media)
    ):
        fail(422, "Можно приложить до 8 разных фотографий.")
    for mid in media:
        m = db.get(Media, valid_id(mid))
        required = (
            "vet" if kind == "vet" else "chat" if kind == "messages" else "public"
        )
        if (
            not m
            or m.owner != me
            or m.scope != required
            or (m.resource and (not existing or m.resource != existing.id))
        ):
            fail(403, "Нет доступа к вложению.")
    return d


@asynccontextmanager
async def lifespan(app):
    if ENV == "production" and (
        DEV or LEGAL_VERSION == "draft-local" or not os.getenv("OTP_WEBHOOK_URL")
    ):
        raise RuntimeError(
            "Production requires OTP provider and approved legal documents"
        )
    if ENV == "production" and any(
        not (Path(os.getenv("LEGAL_DIR", "./legal")) / f"{k}.txt").exists()
        for k in ("privacy", "terms")
    ):
        raise RuntimeError("Approved legal files are required")
    importlib.import_module("migrations.001_initial").migrate()
    importlib.import_module("migrations.002_relationship_pairs").migrate()
    importlib.import_module("migrations.003_unicode_search").migrate()
    yield


app = FastAPI(title="ЗуЗу API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv(
        "CORS_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080"
    ).split(","),
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.exception_handler(IntegrityError)
async def conflict(request, exc):
    return JSONResponse(
        status_code=409,
        content={"detail": "Такая запись уже существует. Обновите экран."},
    )


@app.exception_handler(RequestValidationError)
async def invalid(request, exc):
    return JSONResponse(
        status_code=422, content={"detail": "Проверьте заполненные поля."}
    )


@app.get("/health")
def health():
    return {
        "status": "ok",
        "demo": DEV,
        "legal_version": LEGAL_VERSION,
        "limits": {"photos": MAX_PHOTOS, "photo_bytes": MAX_BYTES, "text": MAX_TEXT},
    }


@app.get("/legal/{kind}")
def legal(kind: str):
    if kind not in ("privacy", "terms"):
        fail(404, "Документ не найден.")
    path = Path(os.getenv("LEGAL_DIR", "./legal")) / f"{kind}.txt"
    return {
        "version": LEGAL_VERSION,
        "approved": LEGAL_VERSION != "draft-local" and path.exists(),
        "text": path.read_text()
        if path.exists()
        else "Локальная тестовая сборка. Утверждённый документ ещё не предоставлен. Не используйте реальные персональные данные до настройки правил и защищённого сервера.",
    }


@app.post("/auth/request")
def request_code(
    body: dict,
    request: Request,
    authorization: str = Header(default=""),
    db=Depends(db_session),
):
    contact = contact_value(body.get("contact", ""))
    ip = request.client.host if request.client else "unknown"
    rate(db, "otp-ip:" + digest(ip), 20, 3600)
    rate(db, "otp-contact:" + digest(contact), 5, 3600)
    last = db.scalar(
        select(Challenge)
        .where(Challenge.contact == contact)
        .order_by(Challenge.created.desc())
    )
    if last and now() - last.created < 60:
        fail(429, "Повторный код можно запросить через 60 секунд.")
    owner = None
    if body.get("link"):
        owner = auth(authorization, db).owner
    cid = uid()
    code = f"{secrets.randbelow(1000000):06d}"
    c = Challenge(
        id=cid,
        contact=contact,
        digest=digest(cid + code),
        expires=now() + 300,
        link_owner=owner,
    )
    if not DEV:
        url = os.getenv("OTP_WEBHOOK_URL")
        if not url:
            fail(503, "Доставка кодов ещё не настроена. Попробуйте позже.")
        try:
            r = httpx.post(
                url,
                json={"contact": contact, "code": code, "expires_in": 300, "id": cid},
                headers={
                    "Authorization": "Bearer " + os.getenv("OTP_WEBHOOK_TOKEN", "")
                },
                timeout=10,
            )
            r.raise_for_status()
        except httpx.HTTPError:
            fail(503, "Не удалось доставить код. Попробуйте позже.")
    db.add(c)
    db.commit()
    return {
        "challenge_id": cid,
        "expires_in": 300,
        "resend_after": 60,
        **({"dev_code": code} if DEV else {}),
    }


@app.post("/auth/verify")
def verify(body: dict, authorization: str = Header(default=""), db=Depends(db_session)):
    cid = valid_id(body.get("challenge_id"))
    c = db.get(Challenge, cid)
    if not c or c.used or c.expires <= now():
        fail(400, "Код истёк. Запросите новый.")
    if c.link_owner and auth(authorization, db).owner != c.link_owner:
        fail(403, "Подтвердите контакт в исходном аккаунте.")
    increment = db.execute(
        update(Challenge)
        .where(
            Challenge.id == cid,
            Challenge.used == False,
            Challenge.attempts < 5,
            Challenge.expires > now(),
        )
        .values(attempts=Challenge.attempts + 1)
    ).rowcount
    db.commit()
    if not increment:
        fail(429, "Попытки закончились. Запросите новый код позже.")
    if not secrets.compare_digest(c.digest, digest(cid + str(body.get("code", "")))):
        fail(400, "Неверный код. Проверьте шесть цифр.")
    if not db.execute(
        update(Challenge)
        .where(Challenge.id == cid, Challenge.used == False)
        .values(used=True)
    ).rowcount:
        fail(400, "Код уже использован.")
    contact = db.get(Contact, c.contact)
    if c.link_owner:
        if contact and contact.owner != c.link_owner:
            fail(
                409,
                "Контакт уже связан с другим аккаунтом. Автоматическое объединение невозможно.",
            )
        if not contact:
            db.add(Contact(contact=c.contact, owner=c.link_owner))
        db.commit()
        return {"linked": True}
    if contact:
        owner = contact.owner
    else:
        if body.get("privacy") != LEGAL_VERSION or body.get("terms") != LEGAL_VERSION:
            fail(422, "Откройте документы и подтвердите каждое согласие.")
        a = Account()
        db.add(a)
        db.flush()
        owner = a.id
        db.add(Contact(contact=c.contact, owner=owner))
        db.add(
            Item(
                id=uid(),
                kind="consents",
                owner=owner,
                data={
                    "privacy": LEGAL_VERSION,
                    "terms": LEGAL_VERSION,
                    "recorded_at": now(),
                },
            )
        )
    token = secrets.token_urlsafe(48)
    device = text_value(body, "device", 80, True)
    db.add(
        LoginSession(
            digest=digest(token), owner=owner, device=device, expires=now() + 30 * 86400
        )
    )
    db.commit()
    return {"token": token, "account_id": owner}


@app.post("/auth/logout")
def logout(s=Depends(auth), db=Depends(db_session)):
    db.execute(delete(Device).where(Device.id == s.device, Device.owner == s.owner))
    db.execute(delete(LoginSession).where(LoginSession.digest == s.digest))
    db.commit()
    return {"ok": True}


@app.get("/me")
def me(s=Depends(auth), db=Depends(db_session)):
    return {
        **profile_json(db, db.get(Account, s.owner), s.owner),
        "contacts": [
            c.contact
            for c in db.scalars(select(Contact).where(Contact.owner == s.owner))
        ],
    }


@app.put("/me/profile")
def save_profile(body: dict, s=Depends(auth), db=Depends(db_session)):
    allowed = {"name", "surname", "status", "photo", "handle"}
    if set(body) - allowed:
        fail(422, "Недопустимые поля профиля.")
    text_value(body, "name", 80, True)
    text_value(body, "surname", 80)
    if body.get("status") not in ("Зоо-блогер", "Эксперт", "Заботливый хозяин"):
        fail(422, "Выберите подпись профиля.")
    handle = text_value(body, "handle", 32, True).lower()
    if not re.fullmatch(r"[a-z0-9_]{3,32}", handle):
        fail(422, "Идентификатор: 3–32 латинских буквы, цифры или _.")
    if handle.startswith("zuzu_"):
        fail(422, "Этот идентификатор зарезервирован.")
    a = db.get(Account, s.owner)
    a.handle = handle
    if body.get("photo"):
        attach_avatar(db, s.owner, body["photo"])
    old = a.profile.get("photo")
    current_pet = pet_for(db, s.owner)
    if (
        old
        and old != body.get("photo")
        and (not current_pet or current_pet.data.get("photo") != old)
    ):
        media = db.get(Media, old)
        if media:
            media.resource = None
    a.profile = {k: v for k, v in body.items() if k != "handle"}
    db.commit()
    return profile_json(db, a, s.owner)


def attach_avatar(db, me, mid):
    m = db.get(Media, valid_id(mid))
    if not m or m.owner != me or m.scope != "public" or m.resource not in (None, me):
        fail(403, "Фотография недоступна.")
    m.resource = me


@app.post("/pets")
def create_pet(body: dict, s=Depends(auth), db=Depends(db_session)):
    if pet_for(db, s.owner):
        fail(409, "В первом релизе доступен один питомец.")
    return save_pet(body, s, db, True)


@app.put("/me/pet")
def update_pet(body: dict, s=Depends(auth), db=Depends(db_session)):
    return save_pet(body, s, db, False)


def save_pet(body, s, db, create):
    fields = {
        "name",
        "handle",
        "species",
        "breed",
        "description",
        "city",
        "photo",
        "birth_date",
        "approx_months",
        "sex",
        "height",
        "weight",
    }
    if set(body) - fields:
        fail(422, "Недопустимые поля питомца.")
    for k in ("name", "species", "city"):
        text_value(body, k, 100, True)
    for k in ("breed", "description"):
        text_value(body, k, 1000)
    handle = text_value(body, "handle", 32, True).lower()
    if not re.fullmatch(r"[a-z0-9_]{3,32}", handle):
        fail(422, "Идентификатор: 3–32 латинских буквы, цифры или _.")
    d = dict(body)
    d.pop("handle")
    d["search_name"] = str(d["name"]).casefold()
    if d.get("birth_date"):
        try:
            born = date.fromisoformat(d["birth_date"])
            if born > datetime.now(timezone.utc).date():
                raise ValueError()
        except (ValueError, TypeError):
            fail(422, "Проверьте дату рождения.")
        d.pop("approx_months", None)
    elif d.get("approx_months") is not None:
        if type(d["approx_months"]) is not int or not 0 <= d["approx_months"] <= 2400:
            fail(422, "Укажите приблизительный возраст в месяцах.")
        d["age_as_of"] = datetime.now(timezone.utc).date().isoformat()
    for key in ("height", "weight"):
        if d.get(key) is not None and (
            not isinstance(d[key], (int, float)) or not 0 < float(d[key]) <= 100000
        ):
            fail(422, "Проверьте рост и вес.")
    if d.get("photo"):
        attach_avatar(db, s.owner, d["photo"])
    p = pet_for(db, s.owner)
    if create:
        p = Pet(owner=s.owner, handle=handle, data=d)
        db.add(p)
    else:
        if not p:
            fail(404, "Сначала создайте питомца.")
        old = p.data.get("photo")
        if (
            old
            and old != d.get("photo")
            and db.get(Account, s.owner).profile.get("photo") != old
        ):
            media = db.get(Media, old)
            if media:
                media.resource = None
        p.handle = handle
        p.data = d
    db.commit()
    return profile_json(db, db.get(Account, s.owner), s.owner)


@app.get("/profiles")
def search_profiles(
    q: str = "", offset: int = 0, s=Depends(auth), db=Depends(db_session)
):
    if len(q) > 100 or offset < 0 or offset > 100000:
        fail(422, "Некорректный запрос.")
    term = q.lower().replace("%", "\\%").replace("_", "\\_")
    stmt = (
        select(Account)
        .join(Pet, Pet.owner == Account.id)
        .where(Account.id.not_in(blocked_ids(db, s.owner)))
    )
    if q:
        stmt = stmt.where(
            or_(
                func.lower(Pet.handle).like("%" + term + "%", escape="\\"),
                Pet.data["search_name"].as_string().like("%" + term + "%", escape="\\"),
            )
        )
    rows = db.scalars(stmt.order_by(Account.id).offset(offset).limit(21)).all()
    return {
        "items": [profile_json(db, a, s.owner) for a in rows[:20]],
        "next": offset + 20 if len(rows) > 20 else None,
    }


@app.get("/profiles/{identifier}")
def profile(identifier: str, s=Depends(auth), db=Depends(db_session)):
    a = db.get(Account, identifier) or db.scalar(
        select(Account).where(Account.handle == identifier)
    )
    if not a:
        p = db.scalar(select(Pet).where(Pet.handle == identifier))
        a = db.get(Account, p.owner) if p else None
    if not a:
        fail(404, "Профиль не найден.")
    allowed_user(db, s.owner, a.id)
    return profile_json(db, a, s.owner)


@app.post("/media")
async def upload(
    scope: str = "public",
    file: UploadFile = File(...),
    s=Depends(auth),
    db=Depends(db_session),
):
    rate(db, "upload:" + s.owner, 30, 3600)
    if scope not in ("public", "vet", "chat"):
        fail(422, "Некорректный тип вложения.")
    raw = await file.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        fail(413, "Фотография должна быть меньше 10 МБ.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            im = Image.open(io.BytesIO(raw))
            if im.format not in ("JPEG", "PNG", "WEBP"):
                fail(422, "Поддерживаются JPEG, PNG и WebP.")
            im.load()
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((4096, 4096))
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        fail(422, "Выберите корректное изображение JPEG, PNG или WebP.")
    m = Media(owner=s.owner, scope=scope)
    db.add(m)
    db.flush()
    im.save(STORE / (m.id + ".jpg"), "JPEG", quality=90)
    db.commit()
    return {"id": m.id}


@app.get("/media/{mid}")
def media(mid: str, s=Depends(auth), db=Depends(db_session)):
    m = db.get(Media, valid_id(mid))
    if not m:
        fail(404, "Файл недоступен.")
    if m.owner != s.owner:
        if m.scope == "vet" or not m.resource:
            fail(404, "Файл недоступен.")
        a = db.get(Account, m.resource)
        if a:
            allowed_user(db, s.owner, a.id)
        else:
            readable(db, s.owner, db.get(Item, m.resource))
    elif m.resource and db.get(Item, m.resource):
        readable(db, s.owner, db.get(Item, m.resource))
    path = STORE / (m.id + ".jpg")
    if not path.exists():
        fail(404, "Файл недоступен.")
    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )


@app.get("/items/{kind}")
def list_items(
    kind: str,
    target: str | None = None,
    parent: str | None = None,
    owner: str | None = None,
    before: float | None = None,
    cursor_id: str = "",
    limit: int = 20,
    west: float | None = None,
    south: float | None = None,
    east: float | None = None,
    north: float | None = None,
    s=Depends(auth),
    db=Depends(db_session),
):
    if kind not in KINDS or kind == "consents" or not 1 <= limit <= 50:
        fail(422, "Некорректный раздел.")
    stmt = select(Item).where(
        Item.kind == kind,
        Item.hidden == False,
        or_(Item.expires == None, Item.expires > now()),
    )
    if kind in PRIVATE:
        stmt = stmt.where(Item.owner == s.owner)
    elif kind == "messages":
        conversation(db, s.owner, target)
        stmt = stmt.where(Item.target == target)
    else:
        stmt = stmt.where(Item.owner.not_in(blocked_ids(db, s.owner)))
        if kind in ("comments", "map_messages"):
            readable(db, s.owner, db.get(Item, target))
            stmt = stmt.where(Item.target == target)
        elif kind == "posts" and not owner:
            following = select(Edge.target).where(
                Edge.kind == "follow", Edge.source == s.owner
            )
            stmt = stmt.where(or_(Item.owner == s.owner, Item.owner.in_(following)))
    if kind == "comments" and parent is not None:
        stmt = stmt.where(
            Item.data["parent_id"].as_string() == None
            if parent == "root"
            else Item.data["parent_id"].as_string() == parent
        )
    if owner:
        allowed_user(db, s.owner, owner)
        stmt = stmt.where(Item.owner == owner)
    if target and kind not in ("messages", "comments", "map_messages"):
        stmt = stmt.where(Item.target == target)
    if kind in ("markers", "news") and all(
        v is not None for v in (west, south, east, north)
    ):
        lat = Item.data["lat"].as_float()
        lng = Item.data["lng"].as_float()
        stmt = stmt.where(lat >= south, lat <= north)
        stmt = stmt.where(
            and_(lng >= west, lng <= east)
            if west <= east
            else or_(lng >= west, lng <= east)
        )
    if before is not None:
        stmt = stmt.where(
            or_(
                Item.created < before, and_(Item.created == before, Item.id < cursor_id)
            )
        )
    rows = db.scalars(
        stmt.order_by(Item.created.desc(), Item.id.desc()).limit(limit + 1)
    ).all()
    return {
        "items": [item_json(db, i, s.owner) for i in rows[:limit]],
        "next": {"before": rows[limit - 1].created, "cursor_id": rows[limit - 1].id}
        if len(rows) > limit
        else None,
    }


@app.get("/item/{iid}")
def get_item(iid: str, s=Depends(auth), db=Depends(db_session)):
    return item_json(db, readable(db, s.owner, db.get(Item, iid)), s.owner)


@app.post("/items/{kind}")
def create_item(kind: str, body: dict, s=Depends(auth), db=Depends(db_session)):
    if kind not in KINDS - {"notifications", "consents"}:
        fail(422, "Некорректный раздел.")
    rate(db, "create:" + s.owner, 120, 60)
    iid = valid_id(body.get("id"))
    prior = db.get(Item, iid)
    if prior:
        if prior.owner != s.owner or prior.kind != kind:
            fail(409, "Этот идентификатор уже занят.")
        return item_json(db, readable(db, s.owner, prior), s.owner)
    target = body.get("target")
    if kind in ("posts", "stories", "vet", "reminders") and not pet_for(db, s.owner):
        fail(422, "Сначала заполните профиль питомца.")
    if kind in ("comments", "map_messages", "reports"):
        parent = readable(db, s.owner, db.get(Item, target))
        if (
            kind == "comments"
            and parent.kind != "posts"
            or kind == "map_messages"
            and parent.kind != "markers"
        ):
            fail(422, "Некорректная запись обсуждения.")
    if kind == "messages":
        conversation(db, s.owner, target)
    d = validate_item(db, s.owner, kind, body.get("data", {}))
    if kind == "comments" and d.get("parent_id"):
        p = readable(db, s.owner, db.get(Item, d["parent_id"]))
        if p.kind != "comments" or p.target != target or p.data.get("parent_id"):
            fail(422, "Ответ можно добавить к корневому комментарию этого поста.")
    if kind == "messages" and d.get("story_id"):
        st = readable(db, s.owner, db.get(Item, d["story_id"]))
        e = conversation(db, s.owner, target)
        if st.kind != "stories" or st.owner not in (e.source, e.target):
            fail(422, "История недоступна в этом диалоге.")
    if kind == "reports":
        d["snapshot"] = {
            "kind": parent.kind,
            "text": parent.data.get("text", ""),
            "title": parent.data.get("title", ""),
            "author_id": parent.owner,
        }
    i = Item(
        id=iid,
        kind=kind,
        owner=s.owner,
        target=target,
        data=d,
        expires=now() + 86400 if kind == "stories" else None,
    )
    db.add(i)
    for mid in d.get("media", []):
        db.get(Media, mid).resource = iid
    if kind == "messages":
        e = conversation(db, s.owner, target)
        other = e.target if e.source == s.owner else e.source
        notification(db, other, "Новое сообщение", "chat", target)
        db.add(
            Outbox(
                owner=other,
                data={
                    "route": "chat",
                    "target": target,
                    "title": "Новое сообщение",
                    "sender": s.owner,
                },
            )
        )
    db.commit()
    return item_json(db, i, s.owner)


@app.put("/item/{iid}")
def edit_item(iid: str, body: dict, s=Depends(auth), db=Depends(db_session)):
    i = readable(db, s.owner, db.get(Item, iid))
    if i.owner != s.owner or i.kind in (
        "messages",
        "reports",
        "feedback",
        "consents",
        "stories",
    ):
        fail(403, "Эту запись нельзя редактировать.")
    d = validate_item(db, s.owner, i.kind, body.get("data", {}), i)
    if i.kind == "notifications":
        d = {**i.data, **d}
    old = set(i.data.get("media", []))
    new = set(d.get("media", []))
    for mid in old - new:
        db.get(Media, mid).resource = None
    for mid in new:
        db.get(Media, mid).resource = iid
    if i.kind == "reminders":
        db.execute(
            delete(Item).where(Item.kind == "notifications", Item.target == i.id)
        )
    i.data = d
    i.updated = now()
    db.commit()
    return item_json(db, i, s.owner)


def remove_item(db, i):
    from sqlalchemy import inspect

    if inspect(i).deleted or i in db.deleted:
        return
    for child in db.scalars(
        select(Item).where(Item.target == i.id, Item.kind != "reports")
    ).all():
        remove_item(db, child)
    # Replies are stored in payload; remove them together with their parent.
    for child in db.scalars(
        select(Item).where(
            Item.kind == "comments", Item.data["parent_id"].as_string() == i.id
        )
    ).all():
        remove_item(db, child)
    for m in db.scalars(select(Media).where(Media.resource == i.id)).all():
        m.resource = (
            None  # Access revoked immediately; GC deletes detached bytes later.
        )
    db.execute(delete(Edge).where(Edge.target == i.id, Edge.kind.in_(["like", "view"])))
    db.delete(i)


@app.delete("/item/{iid}")
def delete_item(iid: str, s=Depends(auth), db=Depends(db_session)):
    i = db.get(Item, iid)
    if not i:
        return {"ok": True}
    if i.owner != s.owner or i.kind in ("consents", "reports"):
        fail(403, "Удалять можно только свои записи.")
    remove_item(db, i)
    db.commit()
    return {"ok": True}


@app.put("/item/{iid}/like")
def like(iid: str, body: dict, s=Depends(auth), db=Depends(db_session)):
    rate(db, "social:" + s.owner, 120, 60)
    i = readable(db, s.owner, db.get(Item, iid))
    if i.kind not in ("posts", "comments", "stories"):
        fail(422, "Реакции недоступны.")
    if type(body.get("active")) is not bool:
        fail(422, "Некорректная реакция.")
    set_edge(db, "like", s.owner, iid, body["active"])
    db.commit()
    return item_json(db, i, s.owner)


def set_edge(db, kind, source, target, active):
    e = db.scalar(
        select(Edge).where(
            Edge.kind == kind, Edge.source == source, Edge.target == target
        )
    )
    if active and not e:
        db.add(Edge(kind=kind, source=source, target=target))
    if not active and e:
        db.delete(e)


@app.get("/item/{iid}/likes")
def likes(iid: str, offset: int = 0, s=Depends(auth), db=Depends(db_session)):
    readable(db, s.owner, db.get(Item, iid))
    ids = db.scalars(
        select(Edge.source)
        .where(
            Edge.kind == "like",
            Edge.target == iid,
            Edge.source.not_in(blocked_ids(db, s.owner)),
        )
        .offset(max(0, offset))
        .limit(21)
    ).all()
    return {
        "items": [profile_json(db, db.get(Account, a), s.owner) for a in ids[:20]],
        "next": offset + 20 if len(ids) > 20 else None,
    }


@app.post("/stories/{iid}/view")
def story_view(iid: str, s=Depends(auth), db=Depends(db_session)):
    i = readable(db, s.owner, db.get(Item, iid))
    if i.kind != "stories":
        fail(404, "История недоступна.")
    set_edge(db, "view", s.owner, iid, True)
    db.commit()
    return {"ok": True}


@app.get("/stories/{iid}/views")
def views(iid: str, offset: int = 0, s=Depends(auth), db=Depends(db_session)):
    i = readable(db, s.owner, db.get(Item, iid))
    if i.owner != s.owner or i.kind != "stories":
        fail(403, "Просмотры доступны только автору.")
    ids = db.scalars(
        select(Edge.source)
        .where(
            Edge.kind == "view",
            Edge.target == iid,
            Edge.source.not_in(blocked_ids(db, s.owner)),
        )
        .offset(max(0, offset))
        .limit(21)
    ).all()
    return {
        "items": [profile_json(db, db.get(Account, a), s.owner) for a in ids[:20]],
        "next": offset + 20 if len(ids) > 20 else None,
    }


@app.put("/relationships/{other}/{action}")
def relationship(
    other: str, action: str, body: dict, s=Depends(auth), db=Depends(db_session)
):
    rate(db, "social:" + s.owner, 120, 60)
    if other == s.owner:
        fail(422, "Нельзя выполнить это действие с собой.")
    if action not in ("block", "follow", "friend"):
        fail(422, "Неизвестное действие.")
    if not db.get(Account, other):
        fail(404, "Профиль недоступен.")
    if action != "block":
        allowed_user(db, s.owner, other)
    active = body.get("active", True)
    if type(active) is not bool:
        fail(422, "Некорректное состояние.")
    if action in ("block", "follow"):
        set_edge(db, action, s.owner, other, active)
        if action == "block" and active:
            db.execute(
                delete(Edge).where(
                    Edge.kind.in_(["follow", "friend"]),
                    or_(
                        and_(Edge.source == s.owner, Edge.target == other),
                        and_(Edge.source == other, Edge.target == s.owner),
                    ),
                )
            )
    else:
        e = db.scalar(
            select(Edge).where(
                Edge.kind == "friend",
                or_(
                    and_(Edge.source == s.owner, Edge.target == other),
                    and_(Edge.source == other, Edge.target == s.owner),
                ),
            )
        )
        op = body.get("operation", "request")
        if op == "request":
            if not e:
                db.add(
                    Edge(kind="friend", source=s.owner, target=other, status="pending")
                )
                notification(db, other, "Заявка в друзья", "profile", s.owner)
        elif op in ("accept", "decline"):
            if not e or e.target != s.owner or e.status != "pending":
                fail(409, "Входящая заявка уже обработана.")
            if op == "accept":
                e.status = "accepted"
            else:
                db.delete(e)
        elif op == "cancel":
            if e and e.source == s.owner and e.status == "pending":
                db.delete(e)
            elif e:
                fail(403, "Нельзя отменить чужую заявку.")
        elif op == "remove":
            if e and e.status == "accepted":
                db.delete(e)
            elif e:
                fail(409, "Это ещё не дружба.")
        else:
            fail(422, "Неизвестное действие.")
    if action == "friend" and body.get("operation") in (
        "accept",
        "decline",
        "cancel",
        "remove",
    ):
        db.execute(
            delete(Item).where(
                Item.kind == "notifications",
                or_(
                    and_(Item.owner == s.owner, Item.target == other),
                    and_(Item.owner == other, Item.target == s.owner),
                ),
                Item.data["route"].as_string() == "profile",
            )
        )
    db.commit()
    return {"ok": True}


@app.get("/relationships")
def relationships(offset: int = 0, s=Depends(auth), db=Depends(db_session)):
    rows = db.scalars(
        select(Edge)
        .where(
            Edge.kind.in_(["friend", "follow", "block"]),
            or_(Edge.source == s.owner, Edge.target == s.owner),
        )
        .order_by(Edge.created.desc(), Edge.id)
        .offset(max(0, offset))
        .limit(51)
    ).all()
    result = []
    for e in rows[:50]:
        if e.kind == "block" and e.source != s.owner:
            continue
        other = e.target if e.source == s.owner else e.source
        a = db.get(Account, other)
        if a:
            result.append(
                {
                    "id": e.id,
                    "kind": e.kind,
                    "source": e.source,
                    "target": e.target,
                    "status": e.status,
                    "profile": profile_json(db, a, s.owner),
                }
            )
    return {"items": result, "next": offset + 50 if len(rows) > 50 else None}


@app.post("/conversations")
def start_chat(body: dict, s=Depends(auth), db=Depends(db_session)):
    other = valid_id(body.get("account_id"))
    if other == s.owner:
        fail(422, "Выберите другого пользователя.")
    allowed_user(db, s.owner, other)
    a, b = sorted([s.owner, other])
    e = db.scalar(
        select(Edge).where(
            Edge.kind == "conversation", Edge.source == a, Edge.target == b
        )
    )
    if not e:
        e = Edge(kind="conversation", source=a, target=b)
        db.add(e)
        db.commit()
    return {"id": e.id}


@app.get("/conversations")
def conversations(
    q: str = "", offset: int = 0, s=Depends(auth), db=Depends(db_session)
):
    last_activity = (
        select(func.max(Item.created))
        .where(Item.kind == "messages", Item.target == Edge.id, Item.hidden == False)
        .correlate(Edge)
        .scalar_subquery()
    )
    stmt = select(Edge).where(
        Edge.kind == "conversation",
        or_(Edge.source == s.owner, Edge.target == s.owner),
        Edge.source.not_in(blocked_ids(db, s.owner)),
        Edge.target.not_in(blocked_ids(db, s.owner)),
    )
    if q:
        matched = select(Pet.owner).where(
            Pet.owner != s.owner,
            or_(
                Pet.data["search_name"]
                .as_string()
                .contains(q.casefold(), autoescape=True),
                Pet.handle.contains(q.lower(), autoescape=True),
            ),
        )
        stmt = stmt.where(or_(Edge.source.in_(matched), Edge.target.in_(matched)))
    rows = db.scalars(
        stmt.order_by(func.coalesce(last_activity, Edge.created).desc(), Edge.id)
        .offset(max(0, offset))
        .limit(51)
    ).all()
    result = []
    for e in rows[:50]:
        other = e.target if e.source == s.owner else e.source
        a = db.get(Account, other)
        if not a:
            continue
        p = profile_json(db, a, s.owner)
        last = db.scalar(
            select(Item)
            .where(Item.kind == "messages", Item.target == e.id, Item.hidden == False)
            .order_by(Item.created.desc())
            .limit(1)
        )
        read = db.scalar(
            select(Edge).where(
                Edge.kind == "read", Edge.source == s.owner, Edge.target == e.id
            )
        )
        count = db.scalar(
            select(func.count())
            .select_from(Item)
            .where(
                Item.kind == "messages",
                Item.target == e.id,
                Item.hidden == False,
                Item.owner != s.owner,
                Item.created > (read.created if read else 0),
            )
        )
        result.append(
            {
                "id": e.id,
                "profile": p,
                "last": item_json(db, last, s.owner) if last else None,
                "unread": count,
            }
        )
    result.sort(key=lambda x: (x["last"] or {}).get("created", 0), reverse=True)
    return {"items": result, "next": offset + 50 if len(rows) > 50 else None}


@app.post("/conversations/{cid}/read")
def mark_read(cid: str, body: dict, s=Depends(auth), db=Depends(db_session)):
    conversation(db, s.owner, cid)
    msg = db.get(Item, body.get("message_id"))
    if not msg or msg.kind != "messages" or msg.target != cid:
        fail(422, "Сообщение не найдено.")
    e = db.scalar(
        select(Edge).where(
            Edge.kind == "read", Edge.source == s.owner, Edge.target == cid
        )
    )
    if not e:
        db.add(Edge(kind="read", source=s.owner, target=cid, created=msg.created))
    else:
        e.created = max(e.created, msg.created)
    db.commit()
    return {"ok": True}


@app.get("/settings")
def settings(s=Depends(auth), db=Depends(db_session)):
    st = db.get(Setting, s.owner)
    return st.data if st else {"push": True, "social": False}


@app.put("/settings")
def save_settings(body: dict, s=Depends(auth), db=Depends(db_session)):
    if set(body) - {"push", "social"} or any(
        type(v) is not bool for v in body.values()
    ):
        fail(422, "Некорректные настройки.")
    st = db.get(Setting, s.owner)
    if not st:
        st = Setting(owner=s.owner, data=body)
        db.add(st)
    else:
        st.data = {**st.data, **body}
    db.commit()
    return st.data


@app.put("/devices")
def device(body: dict, s=Depends(auth), db=Depends(db_session)):
    token = text_value(body, "token", 4096, True)
    d = db.get(Device, s.device)
    if not d:
        d = Device(id=s.device, owner=s.owner, token=token)
        db.add(d)
    else:
        d.owner = s.owner
        d.token = token
    db.commit()
    return {"ok": True}


@app.delete("/me")
def delete_account(body: dict, s=Depends(auth), db=Depends(db_session)):
    if body.get("confirmation") != "УДАЛИТЬ":
        fail(422, "Введите УДАЛИТЬ для подтверждения.")
    owner = s.owner
    contacts = list(db.scalars(select(Contact.contact).where(Contact.owner == owner)))
    db.execute(
        delete(Challenge).where(
            or_(Challenge.contact.in_(contacts), Challenge.link_owner == owner)
        )
    )
    for contact in contacts:
        db.execute(delete(Rate).where(Rate.key.contains(digest(contact))))
    # Remove authored content and all conversations containing this account.
    cids = list(
        db.scalars(
            select(Edge.id).where(
                Edge.kind == "conversation",
                or_(Edge.source == owner, Edge.target == owner),
            )
        )
    )
    rows = db.scalars(
        select(Item).where(or_(Item.owner == owner, Item.target.in_(cids)))
    ).all()
    for i in rows:
        if db.get(Item, i.id):
            remove_item(db, i)
            db.flush()
    for m in db.scalars(select(Media).where(Media.owner == owner)).all():
        (STORE / (m.id + ".jpg")).unlink(missing_ok=True)
        db.delete(m)
    for model, column in [
        (Contact, Contact.owner),
        (Pet, Pet.owner),
        (LoginSession, LoginSession.owner),
        (Device, Device.owner),
        (Setting, Setting.owner),
        (Outbox, Outbox.owner),
    ]:
        db.execute(delete(model).where(column == owner))
    db.execute(
        delete(Edge).where(
            or_(Edge.source == owner, Edge.target == owner, Edge.target.in_(cids))
        )
    )
    for report in db.scalars(
        select(Item).where(
            Item.kind == "reports",
            Item.data["snapshot"]["author_id"].as_string() == owner,
        )
    ).all():
        report.data = {**report.data, "snapshot": {"deleted": True}}
    db.delete(db.get(Account, owner))
    db.commit()
    return {"ok": True}


def admin(x_admin_key: str = Header(default="")):
    expected = os.getenv("ADMIN_KEY", "")
    if not expected or not secrets.compare_digest(x_admin_key, expected):
        fail(403, "Требуется ключ модератора.")


@app.get("/admin/queue", dependencies=[Depends(admin)])
def queue(offset: int = 0, db=Depends(db_session)):
    rows = db.scalars(
        select(Item)
        .where(Item.kind.in_(["reports", "feedback"]))
        .order_by(Item.created.desc())
        .offset(max(0, offset))
        .limit(50)
    ).all()
    return [
        {
            "id": i.id,
            "kind": i.kind,
            "owner": i.owner,
            "target": i.target,
            "data": i.data,
            "created": i.created,
        }
        for i in rows
    ]


@app.post("/admin/moderate", dependencies=[Depends(admin)])
def moderate(body: dict, db=Depends(db_session)):
    i = db.get(Item, body.get("target"))
    action = body.get("action")
    reason = text_value(body, "reason", 2000, True)
    if not i or action not in ("hide", "restore", "resolve"):
        fail(422, "Проверьте объект и действие.")
    if action == "resolve":
        i.data = {**i.data, "resolved": True}
    elif i.kind in (
        "posts",
        "comments",
        "stories",
        "markers",
        "news",
        "map_messages",
        "messages",
    ):
        i.hidden = action == "hide"
    else:
        fail(403, "Этот объект нельзя скрыть.")
    db.add(Audit(target=i.id, action=action, reason=reason))
    db.commit()
    return {"ok": True}


@app.post("/admin/map", dependencies=[Depends(admin)])
def official_map(body: dict, db=Depends(db_session)):
    iid = valid_id(body.get("id"))
    prior = db.get(Item, iid)
    if prior:
        return {"id": prior.id}
    data = body.get("data", {})
    category = data.get("category")
    if category not in ("factory", "construction"):
        fail(422, "Категория: factory или construction.")
    author = db.scalar(select(Account).where(Account.handle == "zuzu_team"))
    if not author:
        author = Account(
            handle="zuzu_team",
            profile={"name": "Команда ЗуЗу", "status": "Заботливый хозяин"},
        )
        db.add(author)
        db.flush()
    # Reuse geographic validation; only admin route can introduce these categories.
    validated = validate_item(db, author.id, "markers", {**data, "category": "other"})
    validated["category"] = category
    validated["source"] = "Внесено администратором"
    db.add(Item(id=iid, kind="markers", owner=author.id, data=validated))
    db.add(
        Audit(
            target=iid,
            action="create_map",
            reason=text_value(body, "source", 2000, True),
        )
    )
    db.commit()
    return {"id": iid}

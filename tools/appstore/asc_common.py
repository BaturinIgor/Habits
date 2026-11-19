"""Общие помощники для скриптов App Store Connect API (asc_provision_watch, asc_screenshots, asc_submit).

Репозиторий публичный, логи Actions видны всем. Поэтому:
- тела ответов Apple в лог не печатаем: только метод, путь, HTTP-код и коды ошибок Apple;
- ключ, токен, содержимое профилей и сертификатов не печатаем никогда.

pyjwt и requests импортируются лениво, чтобы юнит-тесты работали без них.
"""
import base64
import os
import sys
import time

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_BUNDLE_ID = "com.baturinigor.zenhab"


class ApiError(Exception):
    def __init__(self, method, path, status, codes):
        self.method, self.path, self.status, self.codes = method, path, status, codes
        super().__init__(f"{method} {path} -> HTTP {status} {', '.join(codes)}".strip())


def token(key_id, issuer_id, key_p8):
    import jwt  # pyjwt

    key = key_p8
    if "BEGIN PRIVATE KEY" not in key:
        key = base64.b64decode(key).decode()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def safe_error_codes(response):
    """Из ответа с ошибкой берём только код, статус и поле, к которому относится ошибка.
    detail обрезаем: он объясняет, что не так, и не содержит ключей, но печатать тело целиком нельзя."""
    try:
        errors = response.json().get("errors", [])
    except Exception:
        return []
    out = []
    for e in errors[:5]:
        pointer = (e.get("source") or {}).get("pointer") or (e.get("source") or {}).get("parameter") or ""
        detail = (e.get("detail") or "").replace("\n", " ")[:160]
        out.append(" ".join(x for x in (e.get("code", ""), pointer, f"«{detail}»" if detail else "") if x))
    return out


class Client:
    """Тонкая обёртка над requests. Токен живёт 15 минут, поэтому обновляем его каждые 10."""

    def __init__(self, key_id=None, issuer_id=None, key_p8=None):
        import requests

        self._key = (key_id or os.environ["ASC_KEY_ID"], issuer_id or os.environ["ASC_ISSUER_ID"],
                     key_p8 or os.environ["ASC_KEY_P8"])
        self._session = requests.Session()
        self._issued = 0

    def _auth(self):
        if time.time() - self._issued > 600:
            self._session.headers.update({"Authorization": f"Bearer {token(*self._key)}",
                                          "Content-Type": "application/json"})
            self._issued = time.time()

    def call(self, method, path, ok_statuses=(), **kw):
        self._auth()
        url = API + path if path.startswith("/") else path
        r = self._session.request(method, url, timeout=60, **kw)
        if r.status_code >= 400 and r.status_code not in ok_statuses:
            raise ApiError(method, path.split("?")[0], r.status_code, safe_error_codes(r))
        if r.status_code in ok_statuses or not r.text:
            return {}
        return r.json()

    def get_all(self, path, params=None):
        """GET со всеми страницами (links.next)."""
        params = dict(params or {})
        params.setdefault("limit", 200)
        data, included = [], []
        page = self.call("GET", path, params=params)
        while True:
            data += page.get("data", [])
            included += page.get("included", [])
            nxt = (page.get("links") or {}).get("next")
            if not nxt:
                break
            page = self.call("GET", nxt)
        return data, included

    def put_raw(self, url, data, headers):
        """Загрузка части файла по uploadOperations (без авторизации ASC)."""
        import requests

        r = requests.put(url, data=data, headers=headers, timeout=120)
        if r.status_code >= 400:
            raise ApiError("PUT", "<upload url>", r.status_code, [])


def find_app(client, bundle_id):
    apps = client.call("GET", "/apps", params={"filter[bundleId]": bundle_id})["data"]
    apps = [a for a in apps if a["attributes"].get("bundleId") == bundle_id]
    if not apps:
        raise SystemExit(f"::error::Приложение {bundle_id} не найдено в App Store Connect")
    return apps[0]


def find_version(client, app_id, version):
    found = client.call("GET", f"/apps/{app_id}/appStoreVersions",
                        params={"filter[versionString]": version, "filter[platform]": "IOS"})["data"]
    if not found:
        raise SystemExit(f"::error::Версия {version} не найдена. Сначала запусти workflow «App Store texts».")
    return found[0]


def version_state(version):
    a = version["attributes"]
    return a.get("appVersionState") or a.get("appStoreState") or "UNKNOWN"


def metadata_locales():
    """Языки, для которых есть тексты в docs/appstore/metadata."""
    folder = os.path.join(ROOT, "docs/appstore/metadata")
    return sorted(f[:-3] for f in os.listdir(folder) if f.endswith(".md"))


def die(message):
    print(f"::error::{message}")
    sys.exit(1)

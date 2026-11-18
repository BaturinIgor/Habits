#!/usr/bin/env python3
"""Заполняет «Что нового» для версии в App Store Connect из docs/appstore/metadata/<locale>.md.

Создаёт версию, если её ещё нет, ставит автоматический выпуск и, если сборка уже
обработана, прикрепляет её. На проверку НЕ отправляет.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (текст .p8 или base64),
APP_BUNDLE_ID, VERSION, BUILD_NUMBER (необязательно).
"""
import base64
import glob
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = os.path.join(os.path.dirname(__file__), "..", "..")


def token():
    key = os.environ["ASC_KEY_P8"]
    if "BEGIN PRIVATE KEY" not in key:
        key = base64.b64decode(key).decode()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


S = requests.Session()
S.headers.update({"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})


def call(method, path, **kw):
    r = S.request(method, API + path if path.startswith("/") else path, **kw)
    if r.status_code >= 400:
        print(f"::error::{method} {path} -> {r.status_code}: {r.text[:1500]}")
        sys.exit(1)
    return r.json() if r.text else {}


def whats_new_texts():
    texts = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "docs/appstore/metadata/*.md"))):
        locale = os.path.basename(path)[:-3]
        text = open(path, encoding="utf-8").read()
        marker = "## What's New"
        if marker not in text:
            continue
        body = text[text.index(marker) + len(marker):]
        if "\n## " in body:
            body = body[:body.index("\n## ")]
        body = body.strip()
        if len(body) > 4000:
            print(f"::error::{locale}: What's New длиннее 4000 символов")
            sys.exit(1)
        texts[locale] = body
    return texts


def main():
    bundle = os.environ.get("APP_BUNDLE_ID") or "com.baturinigor.zenhab"
    version = os.environ["VERSION"]
    build_number = os.environ.get("BUILD_NUMBER", "").strip()

    apps = call("GET", "/apps", params={"filter[bundleId]": bundle})["data"]
    if not apps:
        print(f"::error::Приложение {bundle} не найдено")
        sys.exit(1)
    app_id = apps[0]["id"]

    found = call("GET", f"/apps/{app_id}/appStoreVersions",
                 params={"filter[versionString]": version, "filter[platform]": "IOS"})["data"]
    if found:
        ver = found[0]
        print(f"Версия {version} уже есть, статус: {ver['attributes'].get('appStoreState')}")
    else:
        ver = call("POST", "/appStoreVersions", json={"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})["data"]
        print(f"Создана версия {version}")
    ver_id = ver["id"]

    call("PATCH", f"/appStoreVersions/{ver_id}", json={"data": {
        "type": "appStoreVersions", "id": ver_id, "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    print("Выпуск: автоматически после одобрения")

    existing = {loc["attributes"]["locale"]: loc["id"] for loc in
                call("GET", f"/appStoreVersions/{ver_id}/appStoreVersionLocalizations",
                     params={"limit": 50})["data"]}
    for locale, text in whats_new_texts().items():
        if locale in existing:
            call("PATCH", f"/appStoreVersionLocalizations/{existing[locale]}", json={"data": {
                "type": "appStoreVersionLocalizations", "id": existing[locale],
                "attributes": {"whatsNew": text}}})
        else:
            call("POST", "/appStoreVersionLocalizations", json={"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale, "whatsNew": text},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
        print(f"  {locale}: «Что нового» заполнено")

    if build_number:
        builds = call("GET", "/builds", params={
            "filter[app]": app_id, "filter[version]": build_number,
            "filter[preReleaseVersion.version]": version})["data"]
        valid = [b for b in builds if b["attributes"].get("processingState") == "VALID"]
        if valid:
            call("PATCH", f"/appStoreVersions/{ver_id}/relationships/build",
                 json={"data": {"type": "builds", "id": valid[0]["id"]}})
            print(f"Сборка {build_number} прикреплена к версии {version}")
        elif builds:
            print(f"::warning::Сборка {build_number} ещё обрабатывается, прикрепи её позже или запусти workflow снова")
        else:
            print(f"::warning::Сборка {build_number} пока не найдена в App Store Connect")
    print("Готово. На проверку не отправлено: проверь версию и нажми «Добавить на проверку».")


if __name__ == "__main__":
    main()

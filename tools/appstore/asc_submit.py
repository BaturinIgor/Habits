#!/usr/bin/env python3
"""Проверяет версию в App Store Connect и отправляет её на ревью.

Проверки:
- версия в состоянии, из которого можно отправить;
- прикреплена сборка и она обработана (VALID), указан ответ про шифрование;
- для всех языков из docs/appstore/metadata есть описание, ключевые слова, URL поддержки,
  «Что нового» (кроме первой версии), название и ссылка на политику конфиденциальности;
- у основного языка есть скриншоты iPhone, все скриншоты обработаны;
- App Privacy («Конфиденциальность приложения»): в публичном API нет, только предупреждение.

Без --confirm yes только проверяет и завершается с ошибкой, ничего не отправляя.
Отправка: reviewSubmission (переиспользуется незавершённая) + элемент с версией + submitted=true.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APP_BUNDLE_ID.

    python3 tools/appstore/asc_submit.py --version 1.6               # только проверки
    python3 tools/appstore/asc_submit.py --version 1.6 --confirm yes # проверки и отправка
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import (DEFAULT_BUNDLE_ID, ApiError, Client, find_app, find_version,  # noqa: E402
                        metadata_locales, version_state)

SUBMITTABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
               "READY_FOR_REVIEW"}
IN_REVIEW = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_DISTRIBUTION",
             "PENDING_APPLE_RELEASE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "ACCEPTED"}
IPHONE_TYPES = ("APP_IPHONE_67", "APP_IPHONE_65")
OPEN_SUBMISSION_STATES = ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")
VERSION_FIELDS = ("description", "keywords", "supportUrl")


# ---------- Чистые функции (покрыты тестами) ----------

class Report:
    def __init__(self):
        self.errors, self.warnings, self.ok = [], [], []

    def error(self, text):
        self.errors.append(text)

    def warn(self, text):
        self.warnings.append(text)

    def good(self, text):
        self.ok.append(text)


def check_build(report, build):
    if not build:
        report.error("к версии не прикреплена сборка (workflow «App Store texts» с номером сборки)")
        return
    a = build["attributes"]
    if a.get("processingState") != "VALID":
        report.error(f"сборка {a.get('version')} в состоянии {a.get('processingState')}, нужна VALID")
        return
    if a.get("expired"):
        report.error(f"сборка {a.get('version')} просрочена")
        return
    if a.get("usesNonExemptEncryption") is None:
        report.warn(f"у сборки {a.get('version')} не указан ответ про шифрование (ITSAppUsesNonExemptEncryption). "
                    f"Если Apple откажет в отправке, ответь в TestFlight -> сборка -> Export Compliance")
    report.good(f"сборка {a.get('version')} обработана")


def check_texts(report, expected_locales, version_locs, info_locs, first_version):
    """version_locs, info_locs: {locale: attributes}."""
    for locale in expected_locales:
        a = version_locs.get(locale)
        if a is None:
            report.error(f"{locale}: нет локализации версии")
            continue
        missing = [f for f in VERSION_FIELDS if not (a.get(f) or "").strip()]
        if not first_version and not (a.get("whatsNew") or "").strip():
            missing.append("whatsNew")
        info = info_locs.get(locale) or {}
        if not (info.get("name") or "").strip():
            missing.append("name")
        if missing:
            report.error(f"{locale}: не заполнено {', '.join(missing)}")
    extra = sorted(set(version_locs) - set(expected_locales))
    for locale in extra:
        a = version_locs[locale]
        if not all((a.get(f) or "").strip() for f in VERSION_FIELDS):
            report.error(f"{locale}: язык есть в версии, но тексты не заполнены")
    if not any((i or {}).get("privacyPolicyUrl") for i in info_locs.values()):
        report.error("не задана ссылка на политику конфиденциальности (Privacy Policy URL)")
    if not report.errors:
        report.good(f"тексты есть для {len(version_locs)} языков")


def check_screenshots(report, primary_locale, shots_by_locale):
    """shots_by_locale: {locale: {display_type: [state, ...]}}."""
    primary = shots_by_locale.get(primary_locale) or {}
    if not any(primary.get(t) for t in IPHONE_TYPES):
        report.error(f"{primary_locale}: нет скриншотов iPhone 6.9\"/6.5\" ({' или '.join(IPHONE_TYPES)})")
    for locale, sets in sorted(shots_by_locale.items()):
        for kind, states in sets.items():
            bad = [s for s in states if s != "COMPLETE"]
            if bad:
                report.error(f"{locale} {kind}: {len(bad)} скриншотов не обработаны ({', '.join(sorted(set(map(str, bad))))})")
    without = sorted(l for l, s in shots_by_locale.items() if not any(s.values()))
    if without:
        report.warn(f"без своих скриншотов (будут показаны скриншоты {primary_locale}): {', '.join(without)}")
    if not report.errors:
        report.good("скриншоты на месте")


def submission_plan(open_submissions, version_id):
    """open_submissions: [{"id", "state", "version_ids"}]. Возвращает ("reuse", id, нужно_добавить_версию),
    ("done", id, False), если версия уже ждёт ревью, или ("create", None, True). Берём незавершённую отправку, в которой уже есть эта версия, иначе любую открытую."""
    for s in open_submissions:
        if version_id in s["version_ids"]:
            if s["state"] in OPEN_SUBMISSION_STATES:
                return "reuse", s["id"], False
            return "done", s["id"], False
    for s in open_submissions:
        if s["state"] in OPEN_SUBMISSION_STATES:
            return "reuse", s["id"], True
    return "create", None, True


def submission_payload(app_id):
    return {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}


def item_payload(submission_id, version_id):
    return {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}}


def submit_payload(submission_id):
    return {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}}


# ---------- Работа с API ----------

def collect(client, app, ver):
    app_id, ver_id = app["id"], ver["id"]
    build = client.call("GET", f"/appStoreVersions/{ver_id}/build").get("data")
    locs, _ = client.get_all(f"/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    version_locs = {l["attributes"]["locale"]: l["attributes"] for l in locs}

    infos = client.call("GET", f"/apps/{app_id}/appInfos")["data"]
    editable = [i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state"))
                not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO")]
    info = (editable or infos)[0]
    info_locs = {l["attributes"]["locale"]: l["attributes"]
                 for l in client.get_all(f"/appInfos/{info['id']}/appInfoLocalizations")[0]}

    shots = {}
    for l in locs:
        sets = client.get_all(f"/appStoreVersionLocalizations/{l['id']}/appScreenshotSets")[0]
        shots[l["attributes"]["locale"]] = {
            s["attributes"]["screenshotDisplayType"]: [
                (x["attributes"].get("assetDeliveryState") or {}).get("state")
                for x in client.get_all(f"/appScreenshotSets/{s['id']}/appScreenshots")[0]]
            for s in sets}

    versions, _ = client.get_all(f"/apps/{app_id}/appStoreVersions", params={"filter[platform]": "IOS"})
    first_version = all(v["id"] == ver_id for v in versions)
    return build, version_locs, info_locs, shots, first_version


def open_submissions(client, app_id):
    subs, _ = client.get_all("/reviewSubmissions", params={
        "filter[app]": app_id, "filter[platform]": "IOS",
        "filter[state]": ",".join(OPEN_SUBMISSION_STATES + ("WAITING_FOR_REVIEW", "IN_REVIEW"))})
    result = []
    for s in subs:
        items, _ = client.get_all(f"/reviewSubmissions/{s['id']}/items", params={"include": "appStoreVersion"})
        ids = [((i.get("relationships") or {}).get("appStoreVersion") or {}).get("data") for i in items]
        result.append({"id": s["id"], "state": s["attributes"].get("state"),
                       "version_ids": [d["id"] for d in ids if d]})
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--confirm", default="", help="yes, чтобы действительно отправить")
    args = parser.parse_args(argv)

    bundle = os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID
    client = Client()
    try:
        app = find_app(client, bundle)
        ver = find_version(client, app["id"], args.version)
        state = version_state(ver)
        print(f"Версия {args.version}: id {ver['id']}, состояние {state}")
        if state in IN_REVIEW:
            print(f"Версия {args.version} уже отправлена или выпущена ({state}), делать нечего.")
            return
        report = Report()
        if state not in SUBMITTABLE:
            report.error(f"из состояния {state} отправить нельзя")
        build, version_locs, info_locs, shots, first_version = collect(client, app, ver)
        check_build(report, build)
        check_texts(report, metadata_locales(), version_locs, info_locs, first_version)
        primary = app["attributes"].get("primaryLocale") or "en-US"
        check_screenshots(report, primary, shots)
        report.warn("App Privacy («Конфиденциальность приложения») через API не проверить: убедись, что ответы "
                    "опубликованы (App Store Connect -> приложение -> App Privacy -> Publish). Без этого Apple "
                    "не даст отправить версию.")

        for line in report.ok:
            print(f"OK: {line}")
        for line in report.warnings:
            print(f"::warning::{line}")
        if report.errors:
            for line in report.errors:
                print(f"::error::{line}")
            print("Не отправлено: исправь ошибки выше.")
            sys.exit(1)
        if args.confirm != "yes":
            print("::error::Проверки пройдены, но без confirm=yes на ревью не отправляю.")
            sys.exit(1)

        action, sub_id, add_item = submission_plan(open_submissions(client, app["id"]), ver["id"])
        if action == "done":
            print(f"Версия уже в отправке {sub_id}, которая ждёт ревью. Делать нечего.")
            return
        if action == "create":
            sub_id = client.call("POST", "/reviewSubmissions", json=submission_payload(app["id"]))["data"]["id"]
            print(f"Создана отправка на ревью {sub_id}")
        else:
            print(f"Использую незавершённую отправку на ревью {sub_id}")
        if add_item:
            item = client.call("POST", "/reviewSubmissionItems", json=item_payload(sub_id, ver["id"]))["data"]
            print(f"Версия добавлена в отправку, элемент {item['id']}")
        result = client.call("PATCH", f"/reviewSubmissions/{sub_id}", json=submit_payload(sub_id))["data"]
        print(f"Отправлено на ревью: {sub_id}, состояние {result['attributes'].get('state')}")
    except ApiError as e:
        hint = " Ключу API нужна роль Admin или App Manager." if e.status in (401, 403) else ""
        print(f"::error::{e}.{hint}")
        sys.exit(1)


if __name__ == "__main__":
    main()

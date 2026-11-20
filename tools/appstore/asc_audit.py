#!/usr/bin/env python3
"""Только читает App Store Connect и сверяет версию с репозиторием. Ничего не меняет.

Сверяет:
- состояние версии, тип выпуска, прикреплённую сборку;
- «Что нового», описание, ключевые слова, рекламный текст, название и подзаголовок
  по каждому языку с docs/appstore/metadata/<locale>.md;
- скриншоты по каждому языку и размеру: контрольные суммы против docs/appstore/screenshots/final;
- заметки для ревьюера, контакт, возрастной рейтинг, покупки и подписки.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APP_BUNDLE_ID.

    python3 tools/appstore/asc_audit.py --version 1.6
"""
import argparse
import glob
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import DEFAULT_BUNDLE_ID, Client, find_app, find_version, version_state  # noqa: E402
from asc_screenshots import display_type, image_size  # noqa: E402
from asc_whats_new import review_notes, sections, whats_new_texts  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SHOTS = os.path.join(ROOT, "docs/appstore/screenshots/final")


class ReadOnly:
    """Обёртка над Client: пропускает только GET."""

    def __init__(self, client):
        self.c = client

    def call(self, method, path, **kw):
        if method != "GET":
            raise SystemExit(f"::error::аудит не должен делать {method} {path}")
        return self.c.call(method, path, **kw)

    def get_all(self, path, params=None):
        return self.c.get_all(path, params)


problems = []


def bad(text):
    problems.append(text)
    print(f"  ✗ {text}")


def ok(text):
    print(f"  ✓ {text}")


def local_shots(locale):
    """{display_type: [md5, ...]} из репозитория, в порядке файлов."""
    result = {}
    for sub in ("", "watch"):
        for f in sorted(glob.glob(os.path.join(SHOTS, locale, sub, "*.png"))):
            data = open(f, "rb").read()
            kind = display_type(image_size(data))
            result.setdefault(kind, []).append(hashlib.md5(data).hexdigest())
    return result


def same(a, b):
    return (a or "").strip() == (b or "").strip()


def safe(label, fn):
    try:
        fn()
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"  ? {label}: не прочитано ({e})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    args = p.parse_args()
    client = ReadOnly(Client())
    bundle = os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID
    app = find_app(client, bundle)
    ver = find_version(client, app["id"], args.version)
    vid = ver["id"]

    print(f"== Версия {args.version}")
    print(f"  состояние: {version_state(ver)}, выпуск: {ver['attributes'].get('releaseType')}")
    build = client.call("GET", f"/appStoreVersions/{vid}/build").get("data")
    if not build:
        bad("сборка не прикреплена")
    else:
        a = build["attributes"]
        ok(f"сборка {a.get('version')}: {a.get('processingState')}, expired={a.get('expired')}, "
           f"шифрование={a.get('usesNonExemptEncryption')}, загружена {a.get('uploadedDate')}")

    print("== Тексты")
    locs, _ = client.get_all(f"/appStoreVersions/{vid}/appStoreVersionLocalizations")
    locs = {l["attributes"]["locale"]: l for l in locs}
    repo_locales = sorted(os.path.basename(f)[:-3]
                          for f in glob.glob(os.path.join(ROOT, "docs/appstore/metadata/*.md")))
    print(f"  языки в версии ({len(locs)}): {', '.join(sorted(locs))}")
    for missing in sorted(set(repo_locales) - set(locs)):
        bad(f"{missing}: есть в репозитории, нет в версии")
    wn = whats_new_texts()
    infos = client.call("GET", f"/apps/{app['id']}/appInfos")["data"]
    editable = [i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state"))
                not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO")]
    info = (editable or infos)[0]
    print(f"  appInfo: {info['attributes'].get('appStoreState') or info['attributes'].get('state')}")
    info_locs = {l["attributes"]["locale"]: l["attributes"]
                 for l in client.get_all(f"/appInfos/{info['id']}/appInfoLocalizations")[0]}
    for locale in sorted(locs):
        a = locs[locale]["attributes"]
        sec = sections(locale)
        ia = info_locs.get(locale, {})
        diffs = []
        for field, want in (("whatsNew", wn.get(locale)), ("description", sec.get("Description")),
                            ("keywords", sec.get("Keywords")), ("promotionalText", sec.get("Promotional text"))):
            if want is None:
                diffs.append(f"{field}: в репозитории нет")
            elif not same(a.get(field), want):
                diffs.append(f"{field} отличается")
        for field, want in (("name", sec.get("Name")), ("subtitle", sec.get("Subtitle"))):
            if want and not same(ia.get(field), want):
                diffs.append(f"{field} отличается ('{ia.get(field)}' vs '{want}')")
        if not a.get("supportUrl"):
            diffs.append("нет supportUrl")
        if not ia.get("privacyPolicyUrl"):
            diffs.append("нет privacyPolicyUrl")
        if diffs:
            bad(f"{locale}: {'; '.join(diffs)}")
        else:
            ok(f"{locale}: тексты совпадают с репозиторием")

    print("== Скриншоты")
    all_new = set()
    for loc in os.listdir(SHOTS):
        if os.path.isdir(os.path.join(SHOTS, loc)):
            for v in local_shots(loc).values():
                all_new.update(v)
    for locale in sorted(locs):
        sets = client.get_all(f"/appStoreVersionLocalizations/{locs[locale]['id']}/appScreenshotSets")[0]
        want = local_shots(locale) if os.path.isdir(os.path.join(SHOTS, locale)) else None
        if not sets:
            ok(f"{locale}: своих скриншотов нет -> App Store покажет скриншоты основного языка")
            continue
        for s in sorted(sets, key=lambda s: s["attributes"]["screenshotDisplayType"]):
            kind = s["attributes"]["screenshotDisplayType"]
            shots = client.get_all(f"/appScreenshotSets/{s['id']}/appScreenshots")[0]
            sums = [x["attributes"].get("sourceFileChecksum") for x in shots]
            states = {(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in shots}
            fresh = sum(1 for c in sums if c in all_new)
            label = f"{locale} {kind}: {len(shots)} шт., из них новых 1.6: {fresh}, {sorted(map(str, states))}"
            if want is not None:
                if want.get(kind) == sums:
                    ok(label + " — точно как в репозитории")
                elif kind in want:
                    bad(label + f" — не совпадает с репозиторием ({len(want[kind])} файлов)")
                else:
                    bad(label + " — такого размера в репозитории нет (лишний набор со старыми картинками)")
            elif sums and fresh == len(sums):
                ok(label)
            else:
                bad(label + " — СТАРЫЕ скриншоты (для этого языка папки в репозитории нет)")

    print("== Ревью")
    detail = client.call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if not detail:
        bad("нет App Review Information")
    else:
        a = detail["attributes"]
        if same(a.get("notes"), review_notes()):
            ok(f"заметки совпадают с репозиторием ({len(a.get('notes') or '')} символов)")
        else:
            bad("заметки отличаются от docs/appstore/review-notes.md")
        for f in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            if not a.get(f):
                bad(f"App Review: не заполнено {f}")
        print(f"  demoAccountRequired={a.get('demoAccountRequired')}")

    print("== Рейтинг и категория")
    info_id = info["id"]

    def rating():
        age = client.call("GET", f"/appInfos/{info_id}/ageRatingDeclaration").get("data")
        (ok if age else bad)(f"возрастной рейтинг: {'есть' if age else 'НЕТ'}")
        cat = client.call("GET", f"/appInfos/{info_id}/primaryCategory").get("data")
        (ok if cat else bad)(f"основная категория: {cat['id'] if cat else 'НЕТ'}")
    safe("рейтинг и категория", rating)

    print("== Покупки")

    def purchases():
        for i in client.get_all(f"/apps/{app['id']}/inAppPurchasesV2")[0]:
            print(f"  {i['attributes'].get('productId')}: {i['attributes'].get('state')}")
        for g in client.get_all(f"/apps/{app['id']}/subscriptionGroups")[0]:
            for s in client.get_all(f"/subscriptionGroups/{g['id']}/subscriptions")[0]:
                print(f"  {s['attributes'].get('productId')}: {s['attributes'].get('state')}")
    safe("покупки", purchases)

    print()
    if problems:
        print(f"ИТОГ: проблем {len(problems)}")
        for t in problems:
            print(f"::warning::{t}")
    else:
        print("ИТОГ: всё совпадает с репозиторием")


if __name__ == "__main__":
    main()

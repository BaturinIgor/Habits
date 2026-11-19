#!/usr/bin/env python3
"""Загружает скриншоты в версию App Store Connect по всем языкам, заменяя старые наборы.

Структура папки (--dir), имена языков как в App Store Connect (как в docs/appstore/metadata):

    <dir>/en-US/01.png 02.png ...      iPhone, обычно 1320x2868 из make_screenshots.py
    <dir>/en-US/watch/01.png ...       Apple Watch (необязательно)
    <dir>/ru/...

Тип экрана определяется по размеру картинки. 1320x2868, 1290x2796 и 1260x2736 (iPhone 6.9")
в API называются APP_IPHONE_67: отдельного типа для 6.9" в App Store Connect API нет.
Наборы, где те же файлы уже лежат (совпадают MD5 и порядок), не трогаем. Иначе грузим новые
и только после их обработки удаляем старые (если вместе их не больше 10; иначе сначала удаляем). Языки без папки пропускаем: App Store покажет
скриншоты основного языка.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APP_BUNDLE_ID.

    python3 tools/appstore/asc_screenshots.py --version 1.6 --dir appstore-shots --dry-run
    python3 tools/appstore/asc_screenshots.py --version 1.6 --dir appstore-shots
"""
import argparse
import hashlib
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import DEFAULT_BUNDLE_ID, ApiError, Client, find_app, find_version, version_state  # noqa: E402

EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                   "INVALID_BINARY"}
MAX_PER_SET = 10
IMAGE_EXT = (".png", ".jpg", ".jpeg")

# Размеры (портрет) -> тип экрана в API. Альбомные тоже принимаем (переворачиваем пару).
SIZES = {
    (1320, 2868): "APP_IPHONE_67", (1290, 2796): "APP_IPHONE_67", (1260, 2736): "APP_IPHONE_67",
    (1284, 2778): "APP_IPHONE_65", (1242, 2688): "APP_IPHONE_65",
    (1206, 2622): "APP_IPHONE_61", (1179, 2556): "APP_IPHONE_61",
    (1242, 2208): "APP_IPHONE_55",
    (422, 514): "APP_WATCH_ULTRA", (410, 502): "APP_WATCH_ULTRA",
    (416, 496): "APP_WATCH_SERIES_10",
    (396, 484): "APP_WATCH_SERIES_7",
    (368, 448): "APP_WATCH_SERIES_4",
    (312, 390): "APP_WATCH_SERIES_3",
}


# ---------- Чистые функции (покрыты тестами) ----------

def image_size(data):
    """(ширина, высота) для PNG и JPEG по заголовку, без Pillow."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        if len(data) < 24 or data[12:16] != b"IHDR":
            raise ValueError("битый PNG: нет заголовка IHDR")
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                i += 2
                continue
            length = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + length
    raise ValueError("не PNG и не JPEG")


def display_type(size):
    w, h = size
    return SIZES.get((w, h)) or SIZES.get((h, w))


def md5(data):
    return hashlib.md5(data).hexdigest()


def plan_set(existing, new):
    """existing: [{"id", "fileName", "checksum", "state"}] в порядке набора; new: [{"fileName", "checksum"}].
    "keep", если в наборе уже ровно эти файлы в том же порядке и все обработаны, иначе "replace"."""
    same = ([e.get("checksum") for e in existing] == [n["checksum"] for n in new]
            and all(e.get("state") == "COMPLETE" for e in existing))
    return "keep" if same and existing else "replace"


def local_sets(locale_dir):
    """{тип экрана: [{"path", "fileName", "checksum", "size"}]} для папки языка (и её подпапки watch).
    Ошибки (неизвестный размер, больше 10 файлов) возвращаются списком."""
    sets, errors = {}, []
    for sub in ("", "watch"):
        folder = os.path.join(locale_dir, sub)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            path = os.path.join(folder, name)
            # ._01.png и прочие скрытые файлы — мусор macOS в архивах.
            if name.startswith(".") or not name.lower().endswith(IMAGE_EXT) or os.path.islink(path):
                continue
            with open(path, "rb") as f:
                data = f.read()
            try:
                size = image_size(data)
            except ValueError as e:
                errors.append(f"{path}: {e}")
                continue
            kind = display_type(size)
            if kind is None:
                errors.append(f"{path}: размер {size[0]}x{size[1]} не подходит ни под один экран App Store")
                continue
            if (sub == "watch") != kind.startswith("APP_WATCH"):
                errors.append(f"{path}: {kind} лежит не в той папке (часы кладём в watch/)")
                continue
            sets.setdefault(kind, []).append({"path": path, "fileName": name, "checksum": md5(data),
                                              "size": len(data)})
    for kind, files in sets.items():
        if len(files) > MAX_PER_SET:
            errors.append(f"{locale_dir}: {kind} — {len(files)} файлов, максимум {MAX_PER_SET}")
    return sets, errors


def find_shots_root(path, locales, depth=3):
    """Папка, в которой лежат подпапки языков. Ищет в path и глубже (для zip с общей папкой),
    пропуская __MACOSX и скрытые. None, если не нашлось."""
    def visible_dirs(p):
        return sorted(d for d in os.listdir(p) if not d.startswith(".") and d != "__MACOSX"
                      and os.path.isdir(os.path.join(p, d)) and not os.path.islink(os.path.join(p, d)))

    found, level = [], [path]
    for _ in range(depth + 1):
        found += [p for p in level if any(d in locales for d in visible_dirs(p))]
        # В папки, где языки уже нашлись, глубже не идём.
        level = [os.path.join(p, d) for p in level if p not in found for d in visible_dirs(p)]
    if len(found) > 1:
        others = ", ".join(os.path.relpath(p, path) for p in found[1:])
        print(f"::warning::Папки языков есть в нескольких местах. Беру {os.path.relpath(found[0], path)}, "
              f"пропускаю: {others}")
    return found[0] if found else None


def screenshot_payload(set_id, file_name, file_size):
    return {"data": {"type": "appScreenshots", "attributes": {"fileName": file_name, "fileSize": file_size},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}


def commit_payload(shot_id, checksum):
    return {"data": {"type": "appScreenshots", "id": shot_id,
                     "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}}


def set_payload(localization_id, kind):
    return {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}}


# ---------- Работа с API ----------

def existing_shots(client, set_id):
    shots, _ = client.get_all(f"/appScreenshotSets/{set_id}/appScreenshots")
    return [{"id": s["id"], "fileName": s["attributes"].get("fileName"),
             "checksum": s["attributes"].get("sourceFileChecksum"),
             "state": ((s["attributes"].get("assetDeliveryState") or {}).get("state"))} for s in shots]


def upload(client, set_id, item, created=None):
    """Загружает один скриншот. id созданного скриншота сразу попадает в created,
    чтобы при сбое посреди загрузки его можно было убрать."""
    with open(item["path"], "rb") as f:
        data = f.read()
    shot = client.call("POST", "/appScreenshots", json=screenshot_payload(set_id, item["fileName"], len(data)))["data"]
    if created is not None:
        created.append(shot["id"])
    for op in shot["attributes"].get("uploadOperations") or []:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        client.put_raw(op["url"], chunk, headers)
    client.call("PATCH", f"/appScreenshots/{shot['id']}", json=commit_payload(shot["id"], item["checksum"]))
    return shot["id"]


def wait_processed(client, ids, timeout=300):
    pending, failed = set(ids), []
    deadline = time.time() + timeout
    while pending and time.time() < deadline:
        for sid in list(pending):
            a = client.call("GET", f"/appScreenshots/{sid}")["data"]["attributes"]
            state = (a.get("assetDeliveryState") or {}).get("state")
            if state == "COMPLETE":
                pending.discard(sid)
            elif state == "FAILED":
                pending.discard(sid)
                failed.append(sid)
        if pending:
            time.sleep(5)
    return failed, sorted(pending)


def replace_strategy(existing_count, new_count):
    """upload_first: новые грузим рядом со старыми и удаляем старые только после обработки новых,
    чтобы при сбое набор не остался пустым. Возможно, только если вместе их не больше 10."""
    return "upload_first" if existing_count + new_count <= MAX_PER_SET else "delete_first"


def replace_set(client, set_id, existing, files, label):
    """Заменяет скриншоты набора. При сбое печатает понятную ошибку и завершает работу."""
    strategy = replace_strategy(len(existing), len(files))
    ids = []

    def rollback():
        """При upload_first убираем уже созданные новые скриншоты, чтобы в наборе остались только старые."""
        if strategy != "upload_first":
            return ""
        try:
            for i in ids:
                client.call("DELETE", f"/appScreenshots/{i}", ok_statuses=(404,))
        except ApiError as e:
            return f"старые скриншоты на месте, но новые убрать не удалось ({e})"
        return "старые скриншоты на месте, загруженные новые убраны"

    try:
        if strategy == "delete_first":
            for e in existing:
                client.call("DELETE", f"/appScreenshots/{e['id']}", ok_statuses=(404,))
        for item in files:
            upload(client, set_id, item, created=ids)
        failed, pending = wait_processed(client, ids)
    except ApiError as e:
        state = rollback() or "набор пустой или неполный"
        print(f"::error::{label}: {e}. {state}. Запусти workflow ещё раз.")
        sys.exit(1)
    if failed or pending:
        what = f"Apple не приняла {len(failed)}" if failed else f"не обработаны за 5 минут {len(pending)}"
        state = rollback() or "набор неполный"
        print(f"::error::{label}: {what} из {len(ids)} новых скриншотов, {state}. Запусти workflow ещё раз.")
        sys.exit(1)
    try:
        if strategy == "upload_first":
            for e in existing:
                client.call("DELETE", f"/appScreenshots/{e['id']}", ok_statuses=(404,))
        client.call("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
                    json={"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    except ApiError as e:
        print(f"::error::{label}: новые скриншоты загружены, но {e}. В наборе могут остаться старые "
              f"или порядок может быть другим. Запусти workflow ещё раз.")
        sys.exit(1)
    print(f"{label}: заменено, {len(ids)} шт.")
    return ids


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--dir", required=True, help="папка с подпапками языков")
    parser.add_argument("--dry-run", action="store_true", help="только показать, что изменится")
    parser.add_argument("--locales", help="через запятую, если нужны не все языки")
    parser.add_argument("--prune", action="store_true",
                        help="удалить наборы других размеров iPhone/часов, которых нет в папке")
    args = parser.parse_args(argv)

    if not os.path.isdir(args.dir):
        print(f"::error::Нет папки {args.dir}")
        sys.exit(1)
    bundle = os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID
    client = Client()
    try:
        app = find_app(client, bundle)
        ver = find_version(client, app["id"], args.version)
        state = version_state(ver)
        if state not in EDITABLE_STATES:
            print(f"::error::Версия {args.version} в состоянии {state}, скриншоты менять нельзя")
            sys.exit(1)
        locs, _ = client.get_all(f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")
        locs = {l["attributes"]["locale"]: l["id"] for l in locs}
        wanted = set(args.locales.split(",")) if args.locales else None
        root = find_shots_root(args.dir, set(locs))
        if root is None:
            print(f"::error::В {args.dir} нет ни одной папки языка из версии {args.version} "
                  f"({', '.join(sorted(locs))}). Нужна структура <dir>/<язык>/01.png")
            sys.exit(1)
        if root != args.dir:
            print(f"Папки языков найдены в {os.path.relpath(root, args.dir)}")
        args.dir = root
        on_disk = sorted(d for d in os.listdir(args.dir) if os.path.isdir(os.path.join(args.dir, d))
                         and not d.startswith(".") and d != "__MACOSX")
        for d in on_disk:
            if d not in locs and (wanted is None or d in wanted):
                print(f"::warning::Папка {d}: такого языка нет в версии {args.version}, пропускаю")

        errors, uploaded, changed, processed = [], [], 0, 0
        for locale in sorted(locs):
            if wanted is not None and locale not in wanted:
                continue
            folder = os.path.join(args.dir, locale)
            if not os.path.isdir(folder):
                print(f"{locale}: папки нет, пропускаю (App Store покажет скриншоты основного языка)")
                continue
            sets, errs = local_sets(folder)
            if errs:
                errors += errs
                continue
            if not sets:
                print(f"::warning::{locale}: в папке нет картинок PNG/JPEG, пропускаю")
                continue
            processed += 1
            remote = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in
                      client.get_all(f"/appStoreVersionLocalizations/{locs[locale]}/appScreenshotSets")[0]}
            for kind, files in sorted(sets.items()):
                existing = existing_shots(client, remote[kind]) if kind in remote else []
                decision = plan_set(existing, files)
                if decision == "keep":
                    print(f"{locale} {kind}: без изменений ({len(files)} шт.)")
                    continue
                changed += 1
                order = {"upload_first": "сначала загрузка", "delete_first": "сначала удаление"}
                print(f"{locale} {kind}: заменить {len(existing)} -> {len(files)} шт. "
                      f"({order[replace_strategy(len(existing), len(files))]})")
                if args.dry_run:
                    continue
                set_id = remote.get(kind) or client.call(
                    "POST", "/appScreenshotSets", json=set_payload(locs[locale], kind))["data"]["id"]
                uploaded += replace_set(client, set_id, existing, files, f"{locale} {kind}")
            if args.prune:
                families = {k.startswith("APP_WATCH") for k in sets}
                for kind, set_id in sorted(remote.items()):
                    family = kind.startswith("APP_WATCH")
                    if kind in sets or family not in families or not (kind.startswith("APP_IPHONE") or family):
                        continue
                    changed += 1
                    print(f"{locale} {kind}: удалить набор (--prune)")
                    if not args.dry_run:
                        client.call("DELETE", f"/appScreenshotSets/{set_id}", ok_statuses=(404,))

        if errors:
            for e in errors:
                print(f"::error::{e}")
            sys.exit(1)
        if not processed:
            print(f"::error::В {args.dir} нет ни одной папки языка из версии {args.version} "
                  f"({', '.join(sorted(locs))}). Проверь структуру: <dir>/<язык>/01.png")
            sys.exit(1)
        if args.dry_run:
            print(f"Dry run: языков {processed}, изменится наборов: {changed}. Ничего не загружено.")
            return
        print(f"Готово: языков {processed}, изменено наборов {changed}, загружено скриншотов {len(uploaded)}")
    except ApiError as e:
        print(f"::error::{e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Готовит подпись для Apple Watch: bundle ID, App Groups и профили App Store.

Что делает (всё идемпотентно, повторный запуск ничего не ломает):
1. Регистрирует bundle ID <APP_ID>.watchkitapp и <APP_ID>.watchkitapp.widget (платформа IOS),
   если их ещё нет.
2. Включает на обоих capability App Groups.
3. Привязать конкретную группу group.<APP_ID> к bundle ID через App Store Connect API нельзя
   (в публичном API нет ресурса App Groups). Скрипт проверяет, попала ли группа в профиль,
   и если нет, печатает, где нажать на developer.apple.com.
4. Находит сертификат Apple Distribution (если задан DIST_CERT_P12, берёт именно его).
5. Создаёт профили App Store «ZenHab Watch App Store» и «ZenHab Watch Widget App Store»
   или берёт уже существующие, если они действующие и содержат нужный сертификат и группу.
   Недействительные (после правки capability) удаляет и создаёт заново.
6. Дальше по режиму:
   --install  ставит оба профиля в ~/Library/MobileDevice/Provisioning Profiles (<UUID>.mobileprovision)
              и пишет только их ИМЕНА в $GITHUB_ENV (WATCH_PROFILE_NAME, WATCH_WIDGET_PROFILE_NAME)
              и $GITHUB_OUTPUT (watch_profile_name, watch_widget_profile_name). Для сборки в appstore.yml;
   --create   только проверяет и создаёт всё нужное в Apple (workflow «App Store provisioning»);
   --out DIR  пишет файлы .mobileprovision в папку (локально);
   --dry-run  ничего не меняет, показывает план;
   --store-secrets  (только локально, по желанию) кладёт профили в секреты PROFILE_WATCH* через свой gh.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (текст .p8 или base64),
APP_BUNDLE_ID (по умолчанию com.baturinigor.zenhab), необязательно DIST_CERT_P12 + DIST_CERT_PASSWORD.

    python3 tools/appstore/asc_provision_watch.py --dry-run
    python3 tools/appstore/asc_provision_watch.py --create
    python3 tools/appstore/asc_provision_watch.py --install          # на раннере сборки
    python3 tools/appstore/asc_provision_watch.py --out ~/Desktop/profiles
"""
import argparse
import base64
import datetime as dt
import os
import plistlib
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import DEFAULT_BUNDLE_ID, ApiError, Client  # noqa: E402

PROFILE_TYPE = "IOS_APP_STORE"
DIST_CERT_TYPES = ("DISTRIBUTION", "IOS_DISTRIBUTION")


def targets(app_id):
    """Что готовим: bundle ID, его имя, имя профиля, переменная с именем профиля для сборки, секрет."""
    return [
        {"identifier": f"{app_id}.watchkitapp", "name": "ZenHab Watch",
         "profile": "ZenHab Watch App Store", "env": "WATCH_PROFILE_NAME", "secret": "PROFILE_WATCH"},
        {"identifier": f"{app_id}.watchkitapp.widget", "name": "ZenHab Watch Widget",
         "profile": "ZenHab Watch Widget App Store", "env": "WATCH_WIDGET_PROFILE_NAME",
         "secret": "PROFILE_WATCH_WIDGET"},
    ]


PROFILE_DIRS = ("~/Library/MobileDevice/Provisioning Profiles",
                "~/Library/Developer/Xcode/UserData/Provisioning Profiles")


def install_profile(content_b64, dirs=PROFILE_DIRS):
    """Кладёт профиль туда, где его ищет xcodebuild, под именем <UUID>.mobileprovision. Возвращает имя."""
    info = parse_profile(content_b64)
    data = base64.b64decode(content_b64)
    for d in dirs:
        folder = os.path.expanduser(d)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"{info['uuid']}.mobileprovision")
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, 0o600)
    return info["name"]


def export_names(names, env_file=None, output_file=None):
    """names: {"WATCH_PROFILE_NAME": "...", ...}. Пишет только имена профилей, без содержимого."""
    for path, key in ((env_file, str), (output_file, str.lower)):
        if path:
            with open(path, "a", encoding="utf-8") as f:
                for name, value in names.items():
                    f.write(f"{key(name)}={value}\n")


# ---------- Чистые функции (покрыты тестами) ----------

def bundle_id_payload(identifier, name):
    return {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}}


def capability_payload(bundle_db_id, capability="APP_GROUPS"):
    return {"data": {"type": "bundleIdCapabilities",
                     "attributes": {"capabilityType": capability},
                     "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_db_id}}}}}


def profile_payload(name, bundle_db_id, cert_id):
    return {"data": {"type": "profiles",
                     "attributes": {"name": name, "profileType": PROFILE_TYPE},
                     "relationships": {
                         "bundleId": {"data": {"type": "bundleIds", "id": bundle_db_id}},
                         "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}}


def exact_bundle(found, identifier):
    """filter[identifier] в API ищет не только точное совпадение, поэтому фильтруем сами."""
    return next((b for b in found if b["attributes"].get("identifier") == identifier), None)


def parse_profile(content_b64):
    """Достаёт из .mobileprovision (CMS с plist внутри) нужные поля без openssl."""
    raw = base64.b64decode(content_b64)
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < 0:
        raise ValueError("в профиле не найден plist")
    plist = plistlib.loads(raw[start:end + len(b"</plist>")])
    ent = plist.get("Entitlements", {})
    return {
        "name": plist.get("Name"),
        "uuid": plist.get("UUID"),
        "app_identifier": ent.get("application-identifier", ""),
        "groups": list(ent.get("com.apple.security.application-groups", []) or []),
        "expires": plist.get("ExpirationDate"),
    }


def _rel_ids(profile, rel):
    data = ((profile.get("relationships") or {}).get(rel) or {}).get("data")
    if data is None:
        return []
    return [d["id"] for d in (data if isinstance(data, list) else [data])]


def profile_problems(profile, bundle_db_id, identifier, cert_id, group, now=None):
    """Пустой список, если профиль можно использовать. Иначе причины (без секретных данных)."""
    now = now or dt.datetime.now(dt.timezone.utc)
    a = profile["attributes"]
    problems = []
    if a.get("profileState") != "ACTIVE":
        problems.append(f"состояние {a.get('profileState')}")
    if a.get("profileType") != PROFILE_TYPE:
        problems.append(f"тип {a.get('profileType')}")
    if bundle_db_id not in _rel_ids(profile, "bundleId"):
        problems.append("другой bundle ID")
    if cert_id not in _rel_ids(profile, "certificates"):
        problems.append("нет нужного сертификата")
    content = a.get("profileContent")
    if not content:
        problems.append("нет содержимого")
        return problems
    try:
        info = parse_profile(content)
    except Exception:
        problems.append("не читается")
        return problems
    if not info["app_identifier"].endswith("." + identifier):
        problems.append("application-identifier не совпадает")
    if group not in info["groups"]:
        problems.append(f"нет группы {group}")
    expires = info["expires"]
    if expires is not None:
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=dt.timezone.utc)
        if expires < now + dt.timedelta(days=14):
            problems.append("истекает меньше чем через 14 дней")
    return problems


def decide_profile(existing, bundle_db_id, identifier, cert_id, group, now=None):
    """Решение по профилям с нужным именем: ("reuse", профиль, []) или ("create", None, [id на удаление])."""
    good, bad = None, []
    for p in existing:
        if good is None and not profile_problems(p, bundle_db_id, identifier, cert_id, group, now):
            good = p
        else:
            bad.append(p["id"])
    if good is not None:
        # Лишние профили с тем же именем мешают Xcode выбрать нужный, но трогать действующий не будем.
        return "reuse", good, []
    return "create", None, bad


def serial_hex(value):
    return format(value, "X").lstrip("0") or "0"


def normalize_serial(text):
    return (text or "").upper().replace(":", "").lstrip("0") or "0"


def choose_certificate(certs, serial=None, now=None):
    """Действующий сертификат Apple Distribution. Если известен серийный номер из P12, только он."""
    now = now or dt.datetime.now(dt.timezone.utc)

    def expires(c):
        text = c["attributes"].get("expirationDate") or ""
        try:
            return dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return dt.datetime.min.replace(tzinfo=dt.timezone.utc)

    live = [c for c in certs
            if c["attributes"].get("certificateType") in DIST_CERT_TYPES and expires(c) > now
            and c["attributes"].get("activated", True) is not False]
    if serial:
        live = [c for c in live if normalize_serial(c["attributes"].get("serialNumber")) == normalize_serial(serial)]
    if not live:
        return None
    return max(live, key=expires)


def p12_serial(p12_b64, password):
    """Серийный номер сертификата из секрета DIST_CERT_P12, чтобы профиль был на тот же сертификат,
    которым подписывает appstore.yml. None, если прочитать не удалось."""
    try:
        from cryptography.hazmat.primitives.serialization import pkcs12

        _, cert, _ = pkcs12.load_key_and_certificates(base64.b64decode(p12_b64), (password or "").encode())
        return serial_hex(cert.serial_number) if cert else None
    except Exception:
        return None


# ---------- Работа с API ----------

class Provisioner:
    def __init__(self, client, app_id, dry_run=False):
        self.client, self.app_id, self.dry_run = client, app_id, dry_run
        self.group = f"group.{app_id}"
        self.failed = False

    def ensure_bundle(self, t):
        found = self.client.call("GET", "/bundleIds", params={
            "filter[identifier]": t["identifier"]})["data"]
        bundle = exact_bundle(found, t["identifier"])
        if bundle:
            print(f"bundle ID {t['identifier']}: уже есть ({bundle['attributes'].get('platform')}), id {bundle['id']}")
            return bundle["id"]
        if self.dry_run:
            print(f"[dry-run] bundle ID {t['identifier']}: будет зарегистрирован")
            return None
        bundle = self.client.call("POST", "/bundleIds", json=bundle_id_payload(t["identifier"], t["name"]))["data"]
        print(f"bundle ID {t['identifier']}: зарегистрирован, id {bundle['id']}")
        return bundle["id"]

    def ensure_app_groups(self, t, bundle_db_id):
        if bundle_db_id is None:
            print(f"[dry-run] {t['identifier']}: будет включена capability APP_GROUPS")
            return
        caps = self.client.call("GET", f"/bundleIds/{bundle_db_id}/bundleIdCapabilities")["data"]
        if any(c["attributes"].get("capabilityType") == "APP_GROUPS" for c in caps):
            print(f"{t['identifier']}: App Groups уже включены")
            return
        if self.dry_run:
            print(f"[dry-run] {t['identifier']}: будет включена capability APP_GROUPS")
            return
        self.client.call("POST", "/bundleIdCapabilities", json=capability_payload(bundle_db_id))
        print(f"{t['identifier']}: App Groups включены")

    def find_certificate(self):
        certs, _ = self.client.get_all("/certificates", params={
            "filter[certificateType]": ",".join(DIST_CERT_TYPES)})
        serial = None
        if os.environ.get("DIST_CERT_P12"):
            serial = p12_serial(os.environ["DIST_CERT_P12"], os.environ.get("DIST_CERT_PASSWORD"))
            if serial is None:
                print("::warning::Не удалось прочитать DIST_CERT_P12, беру самый свежий сертификат Apple Distribution")
        cert = choose_certificate(certs, serial)
        if cert is None and serial:
            print("::error::Сертификат из DIST_CERT_P12 не найден среди действующих сертификатов Apple Distribution "
                  "(отозван или истёк). Обнови DIST_CERT_P12 или запусти без него.")
            sys.exit(1)
        if cert is None:
            print("::error::Нет действующего сертификата Apple Distribution. Создай его в Xcode "
                  "(Settings -> Accounts -> Manage Certificates -> + -> Apple Distribution).")
            sys.exit(1)
        source = "из DIST_CERT_P12" if serial else "самый свежий"
        print(f"Сертификат Apple Distribution: id {cert['id']} ({source}), "
              f"действует до {cert['attributes'].get('expirationDate', '?')[:10]}")
        return cert["id"]

    def ensure_profile(self, t, bundle_db_id, cert_id):
        """Возвращает base64 профиля или None."""
        if bundle_db_id is None:
            print(f"[dry-run] профиль «{t['profile']}»: будет создан")
            return None
        existing, _ = self.client.get_all("/profiles", params={
            "filter[name]": t["profile"], "include": "bundleId,certificates"})
        existing = [p for p in existing if p["attributes"].get("name") == t["profile"]]
        action, profile, to_delete = decide_profile(existing, bundle_db_id, t["identifier"], cert_id, self.group)
        if action == "reuse":
            print(f"профиль «{t['profile']}»: действующий, UUID {profile['attributes'].get('uuid')}")
            return profile["attributes"]["profileContent"]
        for p in existing:
            if p["id"] in to_delete:
                reasons = ", ".join(profile_problems(p, bundle_db_id, t["identifier"], cert_id, self.group))
                if self.dry_run:
                    print(f"[dry-run] профиль id {p['id']}: будет удалён ({reasons})")
                    continue
                self.client.call("DELETE", f"/profiles/{p['id']}", ok_statuses=(404,))
                print(f"профиль id {p['id']}: удалён ({reasons})")
        if self.dry_run:
            print(f"[dry-run] профиль «{t['profile']}»: будет создан")
            return None
        created = self.client.call("POST", "/profiles", json=profile_payload(t["profile"], bundle_db_id, cert_id))["data"]
        content = created["attributes"]["profileContent"]
        info = parse_profile(content)
        print(f"профиль «{t['profile']}»: создан, UUID {info['uuid']}")
        if self.group not in info["groups"]:
            self.failed = True
            print(f"::warning::Группа {self.group} не привязана к {t['identifier']}, поэтому её нет в профиле и "
                  f"подпись часов упадёт. App Store Connect API не умеет привязывать группы, нужен один клик: "
                  f"developer.apple.com/account/resources/identifiers -> {t['identifier']} -> App Groups -> "
                  f"Configure (или Edit) -> отметь {self.group} -> Continue -> Save. "
                  f"Затем запусти этот workflow ещё раз: профиль пересоздастся уже с группой.")
            return None
        return content


def gh_ready(repo):
    if not shutil.which("gh"):
        return "не найден gh (brew install gh)"
    r = subprocess.run(["gh", "secret", "list", "--repo", repo], capture_output=True, text=True)
    if r.returncode != 0:
        return "gh не может читать секреты репозитория: нужен токен с правом Secrets: read and write"
    return None


def store_secret(repo, name, value):
    # Значение идёт через stdin, а не аргументом, чтобы не светиться в списке процессов.
    r = subprocess.run(["gh", "secret", "set", name, "--repo", repo], input=value, text=True, capture_output=True)
    if r.returncode != 0:
        print(f"::error::gh secret set {name}: код {r.returncode}")
        sys.exit(1)
    print(f"Секрет {name} сохранён в {repo}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="ничего не менять, только показать план")
    parser.add_argument("--create", action="store_true", help="создать недостающее в Apple, файлы не писать")
    parser.add_argument("--install", action="store_true",
                        help="поставить профили на эту машину и выдать их имена в $GITHUB_ENV/$GITHUB_OUTPUT")
    parser.add_argument("--out", help="папка, куда записать .mobileprovision (локальный режим)")
    parser.add_argument("--store-secrets", action="store_true",
                        help="только локально: положить профили в секреты PROFILE_WATCH* через свой gh")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY") or "BaturinIgor/Habits")
    args = parser.parse_args(argv)

    if not (args.dry_run or args.create or args.install or args.out or args.store_secrets):
        parser.error("укажи --dry-run, --create, --install, --out или --store-secrets")
    if args.store_secrets and not args.dry_run:
        problem = gh_ready(args.repo)
        if problem:
            print(f"::error::{problem}. Выполни gh auth login под владельцем репозитория.")
            sys.exit(1)

    app_id = os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID
    prov = Provisioner(Client(), app_id, dry_run=args.dry_run)
    try:
        cert_id = prov.find_certificate()
        results = {}
        for t in targets(app_id):
            bundle_db_id = prov.ensure_bundle(t)
            prov.ensure_app_groups(t, bundle_db_id)
            results[t["secret"]] = (t, prov.ensure_profile(t, bundle_db_id, cert_id))
    except ApiError as e:
        hint = ""
        if e.status in (401, 403):
            hint = (" Ключ API не имеет доступа к Certificates, Identifiers & Profiles: "
                    "нужен ключ с ролью Admin (или App Manager с доступом к сертификатам).")
        print(f"::error::{e}.{hint}")
        sys.exit(1)

    if args.dry_run:
        print("Dry run: ничего не изменено.")
        return
    if prov.failed:
        print("::error::Не все профили готовы, см. предупреждения выше. Ничего не установлено.")
        sys.exit(1)
    names = {}
    for secret, (t, content) in results.items():
        if args.install:
            names[t["env"]] = install_profile(content)
            print(f"Установлен профиль «{names[t['env']]}» -> {t['env']}")
        if args.out:
            os.makedirs(os.path.expanduser(args.out), exist_ok=True)
            path = os.path.join(os.path.expanduser(args.out), f"{t['profile'].replace(' ', '_')}.mobileprovision")
            with open(path, "wb") as f:
                f.write(base64.b64decode(content))
            print(f"Записан {path}")
        if args.store_secrets:
            store_secret(args.repo, secret, content)
    if names:
        export_names(names, os.environ.get("GITHUB_ENV"), os.environ.get("GITHUB_OUTPUT"))
    print("Готово. Профили для часов на месте.")


if __name__ == "__main__":
    main()

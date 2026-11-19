"""Юнит-тесты для скриптов App Store Connect. Настоящий API не вызывается.

    python3 -m unittest discover -s tools/appstore/tests -v
"""
import base64
import datetime as dt
import io
import os
import plistlib
import struct
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import asc_common  # noqa: E402
import asc_provision_watch as prov  # noqa: E402
import asc_screenshots as shots  # noqa: E402
import asc_submit as submit  # noqa: E402

APP = "com.baturinigor.zenhab"
GROUP = "group." + APP
NOW = dt.datetime(2026, 11, 20, tzinfo=dt.timezone.utc)


def profile_content(identifier, groups=(GROUP,), expires=NOW + dt.timedelta(days=300), uuid="U-1"):
    plist = plistlib.dumps({
        "Name": "x", "UUID": uuid, "ExpirationDate": expires.replace(tzinfo=None),
        "Entitlements": {"application-identifier": "TEAMID." + identifier,
                         "com.apple.security.application-groups": list(groups)}})
    return base64.b64encode(b"\x30\x82CMS-junk" + plist + b"\x00signature").decode()


def profile(pid, identifier, bundle_db="B1", cert="C1", state="ACTIVE", **kw):
    return {"id": pid, "attributes": {"name": "ZenHab Watch App Store", "profileState": state,
                                      "profileType": "IOS_APP_STORE", "uuid": "U-" + pid,
                                      "profileContent": profile_content(identifier, **kw)},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_db}},
                              "certificates": {"data": [{"type": "certificates", "id": cert}]}}}


def png(w, h):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IEND", b""))


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class FakeClient:
    """Подменяет asc_common.Client: маршруты (метод, путь) -> ответ или функция, журнал вызовов."""

    def __init__(self, routes):
        self.routes, self.calls = routes, []

    def call(self, method, path, ok_statuses=(), **kw):
        self.calls.append((method, path, kw.get("json"), kw.get("params")))
        key = (method, path.split("?")[0])
        if key not in self.routes:
            raise AssertionError(f"неожиданный вызов {key}")
        r = self.routes[key]
        return r(kw) if callable(r) else r

    def get_all(self, path, params=None):
        page = self.call("GET", path, params=params)
        return page.get("data", []), page.get("included", [])

    def put_raw(self, url, data, headers):
        self.calls.append(("PUT", url, len(data), headers))

    def writes(self):
        return [(m, p) for m, p, *_ in self.calls if m != "GET"]


# ---------- Профили часов ----------

class ProvisionPureTests(unittest.TestCase):
    def test_targets(self):
        t = prov.targets(APP)
        self.assertEqual([x["identifier"] for x in t], [APP + ".watchkitapp", APP + ".watchkitapp.widget"])
        self.assertEqual([x["secret"] for x in t], ["PROFILE_WATCH", "PROFILE_WATCH_WIDGET"])

    def test_payloads(self):
        self.assertEqual(prov.bundle_id_payload("a.b", "N")["data"]["attributes"],
                         {"identifier": "a.b", "name": "N", "platform": "IOS"})
        cap = prov.capability_payload("B1")["data"]
        self.assertEqual(cap["attributes"]["capabilityType"], "APP_GROUPS")
        self.assertEqual(cap["relationships"]["bundleId"]["data"]["id"], "B1")
        p = prov.profile_payload("Name", "B1", "C1")["data"]
        self.assertEqual(p["attributes"], {"name": "Name", "profileType": "IOS_APP_STORE"})
        self.assertEqual(p["relationships"]["certificates"]["data"], [{"type": "certificates", "id": "C1"}])

    def test_exact_bundle_ignores_prefix_matches(self):
        found = [{"id": "1", "attributes": {"identifier": APP + ".watchkitapp.widget"}},
                 {"id": "2", "attributes": {"identifier": APP + ".watchkitapp"}}]
        self.assertEqual(prov.exact_bundle(found, APP + ".watchkitapp")["id"], "2")
        self.assertIsNone(prov.exact_bundle(found[:1], APP + ".watchkitapp"))

    def test_parse_profile(self):
        info = prov.parse_profile(profile_content(APP + ".watchkitapp"))
        self.assertEqual(info["groups"], [GROUP])
        self.assertTrue(info["app_identifier"].endswith(".watchkitapp"))

    def test_decide_reuse_valid(self):
        ident = APP + ".watchkitapp"
        action, p, delete = prov.decide_profile([profile("P1", ident)], "B1", ident, "C1", GROUP, NOW)
        self.assertEqual((action, p["id"], delete), ("reuse", "P1", []))

    def test_decide_recreate_cases(self):
        ident = APP + ".watchkitapp"
        cases = {
            "invalid": profile("P1", ident, state="INVALID"),
            "no group": profile("P1", ident, groups=()),
            "other cert": profile("P1", ident, cert="C2"),
            "expired": profile("P1", ident, expires=NOW - dt.timedelta(days=1)),
            "wrong id": profile("P1", APP + ".other"),
        }
        for name, p in cases.items():
            with self.subTest(name):
                self.assertEqual(prov.decide_profile([p], "B1", ident, "C1", GROUP, NOW), ("create", None, ["P1"]))

    def test_decide_never_deletes_foreign_profiles(self):
        ident = APP + ".watchkitapp"
        other_bundle = profile("P1", ident, bundle_db="B9")
        other_type = profile("P2", ident)
        other_type["attributes"]["profileType"] = "IOS_APP_DEVELOPMENT"
        broken = profile("P3", ident, state="INVALID")
        self.assertEqual(prov.decide_profile([other_bundle, other_type, broken], "B1", ident, "C1", GROUP, NOW),
                         ("foreign", None, ["P1", "P2"]))

    def test_decide_keeps_valid_expiring_profile(self):
        ident = APP + ".watchkitapp"
        p = profile("P1", ident, expires=NOW + dt.timedelta(days=3))
        self.assertEqual(prov.decide_profile([p], "B1", ident, "C1", GROUP, NOW), ("reuse_expiring", p, []))
        good = profile("P2", ident)
        self.assertEqual(prov.decide_profile([p, good], "B1", ident, "C1", GROUP, NOW), ("reuse", good, []))

    def test_decide_create_when_none(self):
        self.assertEqual(prov.decide_profile([], "B1", "x", "C1", GROUP, NOW), ("create", None, []))

    def test_choose_certificate(self):
        certs = [
            {"id": "old", "attributes": {"certificateType": "DISTRIBUTION", "expirationDate": "2026-01-01T00:00:00.000+0000".replace("+0000", "+00:00"), "serialNumber": "0A"}},
            {"id": "a", "attributes": {"certificateType": "DISTRIBUTION", "expirationDate": "2027-05-01T00:00:00Z", "serialNumber": "1B"}},
            {"id": "b", "attributes": {"certificateType": "IOS_DISTRIBUTION", "expirationDate": "2027-09-01T00:00:00Z", "serialNumber": "2C"}},
            {"id": "dev", "attributes": {"certificateType": "DEVELOPMENT", "expirationDate": "2028-01-01T00:00:00Z", "serialNumber": "3D"}},
        ]
        self.assertEqual(prov.choose_certificate(certs, now=NOW)["id"], "b")
        self.assertEqual(prov.choose_certificate(certs, serial="001b", now=NOW)["id"], "a")
        self.assertIsNone(prov.choose_certificate(certs, serial="0A", now=NOW))
        self.assertEqual(prov.serial_hex(0x1B), "1B")


class ProvisionFlowTests(unittest.TestCase):
    ident = APP + ".watchkitapp"
    target = prov.targets(APP)[0]

    def run_quiet(self, fn, *a):
        with redirect_stdout(io.StringIO()) as out:
            result = fn(*a)
        return result, out.getvalue()

    def test_existing_everything_is_reused_without_writes(self):
        c = FakeClient({
            ("GET", "/bundleIds"): {"data": [{"id": "B1", "attributes": {"identifier": self.ident, "platform": "IOS"}}]},
            ("GET", "/bundleIds/B1/bundleIdCapabilities"): {"data": [{"attributes": {"capabilityType": "APP_GROUPS"}}]},
            ("GET", "/profiles"): {"data": [profile("P1", self.ident)]},
        })
        p = prov.Provisioner(c, APP)
        b, _ = self.run_quiet(p.ensure_bundle, self.target)
        self.run_quiet(p.ensure_app_groups, self.target, b)
        content, _ = self.run_quiet(p.ensure_profile, self.target, b, "C1")
        self.assertEqual(b, "B1")
        self.assertIsNotNone(content)
        self.assertEqual(c.writes(), [])
        self.assertFalse(p.failed)

    def test_missing_things_are_created(self):
        created = profile("P2", self.ident)
        c = FakeClient({
            ("GET", "/bundleIds"): {"data": []},
            ("POST", "/bundleIds"): {"data": {"id": "B1"}},
            ("GET", "/bundleIds/B1/bundleIdCapabilities"): {"data": []},
            ("POST", "/bundleIdCapabilities"): {"data": {"id": "cap"}},
            ("GET", "/profiles"): {"data": [profile("P1", self.ident, state="INVALID")]},
            ("DELETE", "/profiles/P1"): {},
            ("POST", "/profiles"): {"data": created},
        })
        p = prov.Provisioner(c, APP)
        b, _ = self.run_quiet(p.ensure_bundle, self.target)
        self.run_quiet(p.ensure_app_groups, self.target, b)
        content, _ = self.run_quiet(p.ensure_profile, self.target, b, "C1")
        self.assertEqual(content, created["attributes"]["profileContent"])
        self.assertEqual(c.writes(), [("POST", "/bundleIds"), ("POST", "/bundleIdCapabilities"),
                                      ("DELETE", "/profiles/P1"), ("POST", "/profiles")])
        body = [j for m, path, j, _ in c.calls if (m, path) == ("POST", "/bundleIds")][0]
        self.assertEqual(body["data"]["attributes"]["platform"], "IOS")

    def test_foreign_profile_is_not_deleted(self):
        foreign = profile("P1", self.ident, bundle_db="B9")
        c = FakeClient({("GET", "/profiles"): {"data": [foreign]}})
        p = prov.Provisioner(c, APP)
        content, out = self.run_quiet(p.ensure_profile, self.target, "B1", "C1")
        self.assertIsNone(content)
        self.assertTrue(p.failed)
        self.assertEqual(c.writes(), [])
        self.assertIn("другой", out)

    def test_expiring_profile_is_kept(self):
        expiring = profile("P1", self.ident, expires=dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3))
        c = FakeClient({("GET", "/profiles"): {"data": [expiring]}})
        p = prov.Provisioner(c, APP)
        content, out = self.run_quiet(p.ensure_profile, self.target, "B1", "C1")
        self.assertIsNotNone(content)
        self.assertEqual(c.writes(), [])
        self.assertIn("::warning::", out)

    def test_create_failure_is_reported(self):
        def fail(kw):
            raise asc_common.ApiError("POST", "/profiles", 409, ["ENTITY_ERROR"])
        c = FakeClient({("GET", "/profiles"): {"data": []}, ("POST", "/profiles"): fail})
        p = prov.Provisioner(c, APP)
        with self.assertRaises(SystemExit), redirect_stdout(io.StringIO()) as out:
            p.ensure_profile(self.target, "B1", "C1")
        self.assertIn("не создан", out.getvalue())

    def test_install_refuses_unreadable_p12(self):
        with tempfile.TemporaryDirectory() as d:
            c, out, code = self.main_with(self.full_routes(), ["--install"],
                                          {"GITHUB_ENV": os.path.join(d, "env"), "APP_BUNDLE_ID": APP,
                                           "DIST_CERT_P12": "P12"}, serial=None)
            self.assertEqual(code, 1)
            self.assertIn("DIST_CERT_P12", out)
            self.assertFalse(os.path.exists(os.path.join(d, "env")))

    def test_written_profiles_are_private(self):
        with tempfile.TemporaryDirectory() as d:
            prov.install_profile(profile_content(self.ident, uuid="U9"), (d,))
            self.assertEqual(os.stat(os.path.join(d, "U9.mobileprovision")).st_mode & 0o777, 0o600)

    def test_profile_without_group_warns_and_is_not_returned(self):
        c = FakeClient({
            ("GET", "/profiles"): {"data": []},
            ("POST", "/profiles"): {"data": profile("P2", self.ident, groups=())},
        })
        p = prov.Provisioner(c, APP)
        content, out = self.run_quiet(p.ensure_profile, self.target, "B1", "C1")
        self.assertIsNone(content)
        self.assertTrue(p.failed)
        self.assertIn("::warning::", out)
        self.assertIn("App Groups", out)
        self.assertNotIn(profile("P2", self.ident)["attributes"]["profileContent"][:40], out)

    def test_dry_run_writes_nothing(self):
        c = FakeClient({
            ("GET", "/bundleIds"): {"data": []},
        })
        p = prov.Provisioner(c, APP, dry_run=True)
        b, _ = self.run_quiet(p.ensure_bundle, self.target)
        self.run_quiet(p.ensure_app_groups, self.target, b)
        self.run_quiet(p.ensure_profile, self.target, b, "C1")
        self.assertEqual(c.writes(), [])

    def test_requires_mode(self):
        with self.assertRaises(SystemExit), redirect_stdout(io.StringIO()), mock.patch("sys.stderr", io.StringIO()):
            prov.main([])

    def test_local_store_secrets_without_gh_fails_before_apple(self):
        with mock.patch.object(prov, "gh_ready", return_value="нет gh"), \
                mock.patch.object(prov, "Client", side_effect=AssertionError("Apple не должен вызываться")), \
                redirect_stdout(io.StringIO()) as out, self.assertRaises(SystemExit):
            prov.main(["--store-secrets"])
        self.assertIn("gh auth login", out.getvalue())

    def test_install_and_export_names(self):
        content = profile_content(self.ident, uuid="UUID-42")
        with tempfile.TemporaryDirectory() as d:
            dirs = (os.path.join(d, "a"), os.path.join(d, "b"))
            name = prov.install_profile(content, dirs)
            self.assertEqual(name, "x")
            for folder in dirs:
                with open(os.path.join(folder, "UUID-42.mobileprovision"), "rb") as f:
                    self.assertEqual(f.read(), base64.b64decode(content))
            env, out = os.path.join(d, "env"), os.path.join(d, "out")
            prov.export_names({"WATCH_PROFILE_NAME": "ZenHab Watch App Store"}, env, out)
            self.assertEqual(read_text(env), "WATCH_PROFILE_NAME=ZenHab Watch App Store\n")
            self.assertEqual(read_text(out), "watch_profile_name=ZenHab Watch App Store\n")

    def main_with(self, routes, args, env, serial="1ABC"):
        c = FakeClient(routes)
        with mock.patch.object(prov, "Client", return_value=c), mock.patch.dict(os.environ, env, clear=False), \
                mock.patch.object(prov, "p12_serial", return_value=serial), redirect_stdout(io.StringIO()) as out:
            try:
                prov.main(args)
                code = 0
            except SystemExit as e:
                code = e.code
        return c, out.getvalue(), code

    def full_routes(self, groups=(GROUP,)):
        ids = {t["identifier"]: f"B{i}" for i, t in enumerate(prov.targets(APP))}

        def bundles(kw):
            ident = kw["params"]["filter[identifier]"]
            return {"data": [{"id": ids[ident], "attributes": {"identifier": ident, "platform": "IOS"}}]}

        def profiles(kw):
            name = kw["params"]["filter[name]"]
            t = next(t for t in prov.targets(APP) if t["profile"] == name)
            p = profile("P" + ids[t["identifier"]], t["identifier"], bundle_db=ids[t["identifier"]], groups=groups)
            p["attributes"]["name"] = name
            return {"data": [p]}

        routes = {
            ("GET", "/certificates"): {"data": [{"id": "C1", "attributes": {
                "certificateType": "DISTRIBUTION", "expirationDate": "2099-01-01T00:00:00Z",
                "serialNumber": "1ABC"}}]},
            ("GET", "/bundleIds"): bundles,
            ("GET", "/profiles"): profiles,
        }
        for b in ids.values():
            routes[("GET", f"/bundleIds/{b}/bundleIdCapabilities")] = {"data": [{"attributes": {"capabilityType": "APP_GROUPS"}}]}
        return routes

    def test_main_install_writes_profiles_and_only_names(self):
        with tempfile.TemporaryDirectory() as d:
            env_file, out_file = os.path.join(d, "env"), os.path.join(d, "out")
            env = {"GITHUB_ENV": env_file, "GITHUB_OUTPUT": out_file, "APP_BUNDLE_ID": APP, "DIST_CERT_P12": "P12"}
            with mock.patch.object(prov, "PROFILE_DIRS", (os.path.join(d, "profiles"),)), \
                    mock.patch.object(prov, "install_profile", wraps=lambda c: prov.parse_profile(c)["name"]) as inst:
                c, out, code = self.main_with(self.full_routes(), ["--install"], env)
            self.assertEqual(code, 0, out)
            self.assertEqual(inst.call_count, 2)
            self.assertEqual(c.writes(), [])
            exported = read_text(env_file)
            self.assertIn("WATCH_PROFILE_NAME=", exported)
            self.assertIn("WATCH_WIDGET_PROFILE_NAME=", exported)
            self.assertIn("watch_widget_profile_name=", read_text(out_file))
            self.assertNotIn(profile_content(APP + ".watchkitapp")[:40], out + exported)

    def test_main_install_refuses_profile_without_group(self):
        created = profile("PN", self.ident, groups=())
        routes = self.full_routes(groups=())
        routes[("DELETE", "/profiles/PB0")] = {}
        routes[("DELETE", "/profiles/PB1")] = {}
        routes[("POST", "/profiles")] = {"data": created}
        with tempfile.TemporaryDirectory() as d:
            env_file = os.path.join(d, "env")
            with mock.patch.object(prov, "install_profile", side_effect=AssertionError("нельзя ставить")):
                _, out, code = self.main_with(routes, ["--install"],
                                              {"GITHUB_ENV": env_file, "APP_BUNDLE_ID": APP, "DIST_CERT_P12": "P12"})
            self.assertEqual(code, 1)
            self.assertIn("App Groups", out)
            self.assertFalse(os.path.exists(env_file))

    def test_store_secret_uses_stdin(self):
        with mock.patch("subprocess.run") as run, redirect_stdout(io.StringIO()):
            run.return_value.returncode = 0
            prov.store_secret("o/r", "PROFILE_WATCH", "BASE64")
        args, kw = run.call_args
        self.assertEqual(args[0], ["gh", "secret", "set", "PROFILE_WATCH", "--repo", "o/r"])
        self.assertEqual(kw["input"], "BASE64")


# ---------- Скриншоты ----------

class ScreenshotTests(unittest.TestCase):
    def test_image_size_and_type(self):
        self.assertEqual(shots.image_size(png(1320, 2868)), (1320, 2868))
        self.assertEqual(shots.display_type((1320, 2868)), "APP_IPHONE_67")
        self.assertEqual(shots.display_type((2868, 1320)), "APP_IPHONE_67")
        self.assertEqual(shots.display_type((422, 514)), "APP_WATCH_ULTRA")
        self.assertIsNone(shots.display_type((1000, 1000)))
        with self.assertRaises(ValueError):
            shots.image_size(b"GIF89a....")

    def test_jpeg_size(self):
        jpeg = (b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 4) + b"JF"
                + b"\xff\xc0" + struct.pack(">HBHH", 11, 8, 2868, 1320) + b"\x03")
        self.assertEqual(shots.image_size(jpeg + b"\x00" * 10), (1320, 2868))

    def test_plan_set(self):
        new = [{"fileName": "01.png", "checksum": "a"}, {"fileName": "02.png", "checksum": "b"}]
        same = [{"id": "1", "checksum": "a", "state": "COMPLETE"}, {"id": "2", "checksum": "b", "state": "COMPLETE"}]
        self.assertEqual(shots.plan_set(same, new), "keep")
        self.assertEqual(shots.plan_set(list(reversed(same)), new), "replace")
        self.assertEqual(shots.plan_set(same[:1], new), "replace")
        self.assertEqual(shots.plan_set([], new), "replace")
        failed = [dict(same[0]), same[1]]
        failed[0]["state"] = "FAILED"
        self.assertEqual(shots.plan_set(failed, new), "replace")

    def test_local_sets(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "watch"))
            for name, data in (("02.png", png(1320, 2868)), ("01.png", png(1320, 2868)),
                               ("notes.txt", b"x"), (os.path.join("watch", "01.png"), png(422, 514))):
                with open(os.path.join(d, name), "wb") as f:
                    f.write(data)
            sets, errors = shots.local_sets(d)
            self.assertEqual(errors, [])
            self.assertEqual([f["fileName"] for f in sets["APP_IPHONE_67"]], ["01.png", "02.png"])
            self.assertEqual(len(sets["APP_WATCH_ULTRA"]), 1)
            with open(os.path.join(d, "03.png"), "wb") as f:
                f.write(png(800, 600))
            with open(os.path.join(d, "watch", "02.png"), "wb") as f:
                f.write(png(1320, 2868))
            _, errors = shots.local_sets(d)
            self.assertEqual(len(errors), 2)

    def test_upload_flow_replaces_changed_set_only(self):
        with tempfile.TemporaryDirectory() as d:
            for loc in ("en-US", "ru"):
                os.makedirs(os.path.join(d, loc))
                with open(os.path.join(d, loc, "01.png"), "wb") as f:
                    f.write(png(1320, 2868))
            checksum = shots.md5(png(1320, 2868))
            uploads = {"n": 0}

            def new_shot(kw):
                uploads["n"] += 1
                return {"data": {"id": f"N{uploads['n']}", "attributes": {"uploadOperations": [
                    {"method": "PUT", "url": "https://upload.example/x", "offset": 0, "length": 10,
                     "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]}}}

            c = FakeClient({
                ("GET", "/apps"): {"data": [{"id": "A", "attributes": {"bundleId": APP}}]},
                ("GET", "/apps/A/appStoreVersions"): {"data": [{"id": "V", "attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION"}}]},
                ("GET", "/appStoreVersions/V/appStoreVersionLocalizations"): {"data": [
                    {"id": "Len", "attributes": {"locale": "en-US"}}, {"id": "Lru", "attributes": {"locale": "ru"}},
                    {"id": "Lde", "attributes": {"locale": "de-DE"}}]},
                ("GET", "/appStoreVersionLocalizations/Len/appScreenshotSets"): {"data": [
                    {"id": "Sen", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
                ("GET", "/appScreenshotSets/Sen/appScreenshots"): {"data": [
                    {"id": "old", "attributes": {"sourceFileChecksum": checksum, "assetDeliveryState": {"state": "COMPLETE"}}}]},
                ("GET", "/appStoreVersionLocalizations/Lru/appScreenshotSets"): {"data": [
                    {"id": "Sru", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
                ("GET", "/appScreenshotSets/Sru/appScreenshots"): {"data": [
                    {"id": "stale", "attributes": {"sourceFileChecksum": "zzz", "assetDeliveryState": {"state": "COMPLETE"}}}]},
                ("DELETE", "/appScreenshots/stale"): {},
                ("POST", "/appScreenshots"): new_shot,
                ("PATCH", "/appScreenshots/N1"): {},
                ("PATCH", "/appScreenshotSets/Sru/relationships/appScreenshots"): {},
                ("GET", "/appScreenshots/N1"): {"data": {"attributes": {"assetDeliveryState": {"state": "COMPLETE"}}}},
            })
            with mock.patch.object(shots, "Client", return_value=c), redirect_stdout(io.StringIO()) as out:
                shots.main(["--version", "1.6", "--dir", d, "--dry-run"])
            self.assertEqual(c.writes(), [])
            self.assertIn("ru APP_IPHONE_67: заменить 1 -> 1", out.getvalue())
            self.assertIn("en-US APP_IPHONE_67: без изменений", out.getvalue())

            c.calls.clear()
            with mock.patch.object(shots, "Client", return_value=c), redirect_stdout(io.StringIO()):
                shots.main(["--version", "1.6", "--dir", d])
            # Сначала новые, старые удаляются только после обработки новых.
            self.assertEqual(c.writes(), [
                ("POST", "/appScreenshots"), ("PUT", "https://upload.example/x"),
                ("PATCH", "/appScreenshots/N1"), ("DELETE", "/appScreenshots/stale"),
                ("PATCH", "/appScreenshotSets/Sru/relationships/appScreenshots")])
            commit = [j for m, p, j, _ in c.calls if (m, p) == ("PATCH", "/appScreenshots/N1")][0]
            self.assertEqual(commit["data"]["attributes"], {"uploaded": True, "sourceFileChecksum": checksum})


class ScreenshotSafetyTests(unittest.TestCase):
    """Замена набора: при сбое старые скриншоты не теряются, понятные ошибки, поиск папки в архиве."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, rel, data):
        path = os.path.join(self.tmp.name, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    def client(self, old_count=1, fail_put=False, state="COMPLETE"):
        old = [{"id": f"old{i}", "attributes": {"sourceFileChecksum": f"x{i}",
                                                 "assetDeliveryState": {"state": "COMPLETE"}}}
               for i in range(old_count)]
        routes = {
            ("GET", "/apps"): {"data": [{"id": "A", "attributes": {"bundleId": APP}}]},
            ("GET", "/apps/A/appStoreVersions"): {"data": [{"id": "V", "attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION"}}]},
            ("GET", "/appStoreVersions/V/appStoreVersionLocalizations"): {"data": [{"id": "L", "attributes": {"locale": "ru"}}]},
            ("GET", "/appStoreVersionLocalizations/L/appScreenshotSets"): {"data": [
                {"id": "S", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
            ("GET", "/appScreenshotSets/S/appScreenshots"): {"data": old},
            ("POST", "/appScreenshots"): {"data": {"id": "N1", "attributes": {"uploadOperations": [
                {"url": "https://upload.example/x", "offset": 0, "length": 5, "requestHeaders": []}]}}},
            ("PATCH", "/appScreenshots/N1"): {},
            ("GET", "/appScreenshots/N1"): {"data": {"attributes": {"assetDeliveryState": {"state": state}}}},
            ("PATCH", "/appScreenshotSets/S/relationships/appScreenshots"): {},
            ("DELETE", "/appScreenshots/N1"): {},
        }
        for o in old:
            routes[("DELETE", f"/appScreenshots/{o['id']}")] = {}
        c = FakeClient(routes)
        if fail_put:
            def put_raw(url, data, headers):
                raise asc_common.ApiError("PUT", "<upload url>", 503, [])
            c.put_raw = put_raw
        return c

    def run_main(self, c, *extra):
        with mock.patch.object(shots, "Client", return_value=c), redirect_stdout(io.StringIO()) as out:
            try:
                shots.main(["--version", "1.6", "--dir", self.tmp.name, *extra])
                code = 0
            except SystemExit as e:
                code = e.code
        return out.getvalue(), code

    def test_replace_strategy(self):
        self.assertEqual(shots.replace_strategy(3, 7), "upload_first")
        self.assertEqual(shots.replace_strategy(8, 8), "delete_first")

    def test_failed_upload_keeps_old_screenshots(self):
        self.write("ru/01.png", png(1320, 2868))
        c = self.client(fail_put=True)
        out, code = self.run_main(c)
        self.assertEqual(code, 1)
        self.assertNotIn(("DELETE", "/appScreenshots/old0"), c.writes())
        # Созданный, но не догруженный новый скриншот убран: в наборе остались только старые.
        self.assertEqual(c.writes()[-1], ("DELETE", "/appScreenshots/N1"))
        self.assertIn("загруженные новые убраны", out)
        self.assertIn("Запусти workflow ещё раз", out)

    def test_rejected_upload_keeps_old_screenshots(self):
        self.write("ru/01.png", png(1320, 2868))
        c = self.client(state="FAILED")
        out, code = self.run_main(c)
        self.assertEqual(code, 1)
        self.assertNotIn(("DELETE", "/appScreenshots/old0"), c.writes())
        self.assertEqual(c.writes()[-1], ("DELETE", "/appScreenshots/N1"))
        self.assertIn("загруженные новые убраны", out)

    def test_full_set_deletes_first_and_reports_incomplete(self):
        self.write("ru/01.png", png(1320, 2868))
        c = self.client(old_count=10, fail_put=True)
        out, code = self.run_main(c)
        self.assertEqual(code, 1)
        self.assertEqual(c.writes()[0], ("DELETE", "/appScreenshots/old0"))
        self.assertNotIn(("DELETE", "/appScreenshots/N1"), c.writes())
        self.assertIn("набор пустой или неполный", out)

    def test_no_locale_folder_fails(self):
        self.write("de-DE/01.png", png(1320, 2868))
        out, code = self.run_main(self.client())
        self.assertEqual(code, 1)
        self.assertIn("нет ни одной папки языка", out)

    def test_empty_locale_folder_fails(self):
        os.makedirs(os.path.join(self.tmp.name, "ru"))
        out, code = self.run_main(self.client())
        self.assertEqual(code, 1)

    def test_find_root_in_zip_layout(self):
        self.write("__MACOSX/ru/._01.png", b"junk")
        self.write(".hidden/ru/01.png", png(1320, 2868))
        self.write("ZenHab shots/ru/01.png", png(1320, 2868))
        self.write("ZenHab shots/ru/._01.png", b"\x00\x05\x16\x07 AppleDouble")
        root = shots.find_shots_root(self.tmp.name, {"ru", "en-US"})
        self.assertEqual(root, os.path.join(self.tmp.name, "ZenHab shots"))
        sets, errors = shots.local_sets(os.path.join(root, "ru"))
        self.assertEqual(errors, [])
        self.assertEqual(len(sets["APP_IPHONE_67"]), 1)
        self.assertIsNone(shots.find_shots_root(os.path.join(self.tmp.name, "__MACOSX", "ru"), {"en-US"}))

    def test_find_root_warns_when_ambiguous(self):
        self.write("a/ru/01.png", png(1320, 2868))
        self.write("b/en-US/01.png", png(1320, 2868))
        self.write("a/ru/watch/01.png", png(422, 514))
        with redirect_stdout(io.StringIO()) as out:
            root = shots.find_shots_root(self.tmp.name, {"ru", "en-US"})
        self.assertEqual(root, os.path.join(self.tmp.name, "a"))
        self.assertIn("::warning::", out.getvalue())
        self.assertIn("Беру a", out.getvalue())
        self.assertIn("b", out.getvalue().split("пропускаю:")[1])
        with redirect_stdout(io.StringIO()) as out:
            shots.find_shots_root(os.path.join(self.tmp.name, "a"), {"ru"})
        self.assertEqual(out.getvalue(), "")

    def test_dry_run_from_nested_root(self):
        self.write("pack/ru/01.png", png(1320, 2868))
        c = self.client()
        out, code = self.run_main(c, "--dry-run")
        self.assertEqual(code, 0, out)
        self.assertEqual(c.writes(), [])

    def test_truncated_png(self):
        with self.assertRaises(ValueError):
            shots.image_size(b"\x89PNG\r\n\x1a\n\x00\x00")
        with self.assertRaises(ValueError):
            shots.image_size(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dXXXX" + b"\x00" * 8)


# ---------- Отправка на ревью ----------

def full_locs(locales, **override):
    base = {"description": "d", "keywords": "k", "supportUrl": "https://s", "whatsNew": "w"}
    base.update(override)
    return {l: dict(base) for l in locales}


class SubmitTests(unittest.TestCase):
    locales = ["en-US", "ru"]

    def test_check_build(self):
        r = submit.Report()
        submit.check_build(r, None)
        self.assertEqual(len(r.errors), 1)
        r = submit.Report()
        submit.check_build(r, {"attributes": {"processingState": "PROCESSING", "version": "12"}})
        self.assertIn("PROCESSING", r.errors[0])
        r = submit.Report()
        submit.check_build(r, {"attributes": {"processingState": "VALID", "version": "12",
                                              "usesNonExemptEncryption": False}})
        self.assertEqual((r.errors, r.warnings), ([], []))

    def test_check_texts(self):
        info = {l: {"name": "ZenHab", "privacyPolicyUrl": "https://p"} for l in self.locales}
        r = submit.Report()
        submit.check_texts(r, self.locales, full_locs(self.locales), info, first_version=False)
        self.assertEqual(r.errors, [])
        r = submit.Report()
        locs = full_locs(self.locales)
        locs["ru"]["whatsNew"] = ""
        del locs["en-US"]
        submit.check_texts(r, self.locales, locs, info, first_version=False)
        self.assertEqual(len(r.errors), 2)
        r = submit.Report()
        submit.check_texts(r, self.locales, full_locs(self.locales, whatsNew=""), info, first_version=True)
        self.assertEqual(r.errors, [])
        r = submit.Report()
        submit.check_texts(r, self.locales, full_locs(self.locales), {l: {"name": "Z"} for l in self.locales}, False)
        self.assertIn("Privacy Policy", r.errors[0])

    def test_check_screenshots(self):
        r = submit.Report()
        submit.check_screenshots(r, "en-US", {"en-US": {"APP_IPHONE_67": ["COMPLETE"]}, "ru": {}})
        self.assertEqual(r.errors, [])
        self.assertIn("ru", r.warnings[0])
        r = submit.Report()
        submit.check_screenshots(r, "en-US", {"en-US": {"APP_WATCH_ULTRA": ["COMPLETE"]}})
        self.assertEqual(len(r.errors), 1)
        r = submit.Report()
        submit.check_screenshots(r, "en-US", {"en-US": {"APP_IPHONE_67": ["COMPLETE", "FAILED"]}})
        self.assertEqual(len(r.errors), 1)

    def test_submission_plan(self):
        self.assertEqual(submit.submission_plan([], "V"), ("create", None, True))
        self.assertEqual(submit.submission_plan([{"id": "S", "state": "READY_FOR_REVIEW", "version_ids": []}], "V"),
                         ("reuse", "S", True))
        self.assertEqual(submit.submission_plan([{"id": "S", "state": "UNRESOLVED_ISSUES", "version_ids": ["V"]}], "V"),
                         ("reuse", "S", False))
        self.assertEqual(submit.submission_plan([{"id": "S", "state": "WAITING_FOR_REVIEW", "version_ids": ["V"]}], "V"),
                         ("done", "S", False))

    def test_submission_plan_refuses_other_version(self):
        other = {"id": "S15", "state": "READY_FOR_REVIEW", "version_ids": ["V15"]}
        self.assertEqual(submit.submission_plan([other], "V"), ("conflict", "S15", False))
        mixed = {"id": "S", "state": "UNRESOLVED_ISSUES", "version_ids": ["V", "V15"]}
        self.assertEqual(submit.submission_plan([mixed], "V"), ("conflict", "S", False))
        # Отправка 1.5, которая уже на ревью, не открыта: её не трогаем и создаём свою.
        in_review = {"id": "S15", "state": "IN_REVIEW", "version_ids": ["V15"]}
        self.assertEqual(submit.submission_plan([in_review], "V"), ("create", None, True))

    def test_payloads(self):
        self.assertEqual(submit.submission_payload("A")["data"]["attributes"], {"platform": "IOS"})
        item = submit.item_payload("S", "V")["data"]["relationships"]
        self.assertEqual(item["appStoreVersion"]["data"], {"type": "appStoreVersions", "id": "V"})
        self.assertEqual(submit.submit_payload("S")["data"]["attributes"], {"submitted": True})

    def flow_client(self, build_state="VALID"):
        locs = [{"id": f"L{l}", "attributes": dict(locale=l, **v)}
                for l, v in full_locs(submit.metadata_locales()).items()]
        routes = {
            ("GET", "/apps"): {"data": [{"id": "A", "attributes": {"bundleId": APP, "primaryLocale": "en-US"}}]},
            ("GET", "/apps/A/appStoreVersions"): lambda kw: {"data": [
                {"id": "V0", "attributes": {"appVersionState": "READY_FOR_DISTRIBUTION"}},
                {"id": "V", "attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION"}}][
                    1 if "filter[versionString]" in (kw.get("params") or {}) else 0:]},
            ("GET", "/appStoreVersions/V/build"): {"data": {"id": "B", "attributes": {
                "processingState": build_state, "version": "12", "usesNonExemptEncryption": False}}},
            ("GET", "/appStoreVersions/V/appStoreVersionLocalizations"): {"data": locs},
            ("GET", "/apps/A/appInfos"): {"data": [{"id": "I", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}]},
            ("GET", "/appInfos/I/appInfoLocalizations"): {"data": [
                {"attributes": {"locale": l["attributes"]["locale"], "name": "ZenHab", "privacyPolicyUrl": "https://p"}}
                for l in locs]},
            ("GET", "/reviewSubmissions"): {"data": []},
            ("POST", "/reviewSubmissions"): {"data": {"id": "S"}},
            ("POST", "/reviewSubmissionItems"): {"data": {"id": "IT"}},
            ("PATCH", "/reviewSubmissions/S"): {"data": {"id": "S", "attributes": {"state": "WAITING_FOR_REVIEW"}}},
        }
        for l in locs:
            routes[("GET", f"/appStoreVersionLocalizations/{l['id']}/appScreenshotSets")] = {"data": [
                {"id": f"S{l['id']}", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]}
            routes[("GET", f"/appScreenshotSets/S{l['id']}/appScreenshots")] = {"data": [
                {"attributes": {"assetDeliveryState": {"state": "COMPLETE"}}}]}
        return FakeClient(routes)

    def test_refuses_without_confirm(self):
        c = self.flow_client()
        with mock.patch.object(submit, "Client", return_value=c), redirect_stdout(io.StringIO()) as out, \
                self.assertRaises(SystemExit) as e:
            submit.main(["--version", "1.6", "--confirm", "no"])
        self.assertEqual(e.exception.code, 1)
        self.assertEqual(c.writes(), [])
        self.assertIn("confirm=yes", out.getvalue())

    def test_refuses_with_unprocessed_build_even_if_confirmed(self):
        c = self.flow_client(build_state="PROCESSING")
        with mock.patch.object(submit, "Client", return_value=c), redirect_stdout(io.StringIO()), \
                self.assertRaises(SystemExit):
            submit.main(["--version", "1.6", "--confirm", "yes"])
        self.assertEqual(c.writes(), [])

    def test_submits_with_confirm(self):
        c = self.flow_client()
        with mock.patch.object(submit, "Client", return_value=c), redirect_stdout(io.StringIO()) as out:
            submit.main(["--version", "1.6", "--confirm", "yes"])
        self.assertEqual(c.writes(), [("POST", "/reviewSubmissions"), ("POST", "/reviewSubmissionItems"),
                                      ("PATCH", "/reviewSubmissions/S")])
        self.assertIn("App Privacy", out.getvalue())

    def test_open_submission_with_other_version_is_not_submitted(self):
        c = self.flow_client()
        c.routes[("GET", "/reviewSubmissions")] = {"data": [{"id": "S15", "attributes": {"state": "READY_FOR_REVIEW"}}]}
        c.routes[("GET", "/reviewSubmissions/S15/items")] = {"data": [
            {"relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": "V0"}}}}]}
        with mock.patch.object(submit, "Client", return_value=c), redirect_stdout(io.StringIO()) as out, \
                self.assertRaises(SystemExit) as e:
            submit.main(["--version", "1.6", "--confirm", "yes"])
        self.assertEqual(e.exception.code, 1)
        self.assertEqual(c.writes(), [])
        self.assertIn("S15", out.getvalue())

    def test_empty_app_infos(self):
        c = self.flow_client()
        c.routes[("GET", "/apps/A/appInfos")] = {"data": []}
        with mock.patch.object(submit, "Client", return_value=c), redirect_stdout(io.StringIO()), \
                self.assertRaises(SystemExit) as e:
            submit.main(["--version", "1.6", "--confirm", "yes"])
        self.assertIn("appInfos", str(e.exception.code))


# ---------- Общие помощники ----------

class CommonTests(unittest.TestCase):
    def test_errors_are_sanitized(self):
        class Resp:
            status_code = 409
            text = "{...}"

            def json(self):
                return {"errors": [{"code": "ENTITY_ERROR.ATTRIBUTE.REQUIRED", "status": "409",
                                    "source": {"pointer": "/data/attributes/whatsNew"},
                                    "detail": "x" * 500, "meta": {"secret": "TOPSECRET"}}]}

        session = mock.Mock()
        session.request.return_value = Resp()
        client = asc_common.Client.__new__(asc_common.Client)
        client._session, client._issued, client._key = session, 10 ** 12, None
        with self.assertRaises(asc_common.ApiError) as e:
            client.call("POST", "/appStoreVersions")
        text = str(e.exception)
        self.assertIn("409", text)
        self.assertIn("ENTITY_ERROR.ATTRIBUTE.REQUIRED", text)
        self.assertNotIn("TOPSECRET", text)
        self.assertNotIn("xxx", text)
        self.assertNotIn("whatsNew", text)
        self.assertEqual(text, "POST /appStoreVersions -> HTTP 409 ENTITY_ERROR.ATTRIBUTE.REQUIRED")

    def retry_client(self, responses):
        session = mock.Mock()
        session.request.side_effect = responses
        client = asc_common.Client.__new__(asc_common.Client)
        client._session, client._issued, client._key = session, 10 ** 12, None
        client._sleep = mock.Mock()
        return client, session

    @staticmethod
    def resp(status, body="{}"):
        r = mock.Mock()
        r.status_code, r.text = status, body
        r.json.return_value = {"data": []} if status < 400 else {"errors": [{"code": "X"}]}
        return r

    def test_retries_get_on_429_and_5xx(self):
        client, session = self.retry_client([self.resp(429), self.resp(503), self.resp(200)])
        self.assertEqual(client.call("GET", "/apps"), {"data": []})
        self.assertEqual(session.request.call_count, 3)
        self.assertEqual([c.args[0] for c in client._sleep.call_args_list], [2, 4])

    def test_retry_after_is_honored_and_capped(self):
        r1, r2 = self.resp(429), self.resp(429)
        r1.headers, r2.headers = {"Retry-After": "7"}, {"Retry-After": "3600"}
        client, session = self.retry_client([r1, r2, self.resp(200)])
        client.call("GET", "/apps")
        self.assertEqual([c.args[0] for c in client._sleep.call_args_list], [7.0, 60.0])
        self.assertIsNone(asc_common.retry_after(mock.Mock(headers={"Retry-After": "Wed, 21 Oct"})))

    def test_post_not_retried_on_5xx(self):
        client, session = self.retry_client([self.resp(500), self.resp(200)])
        with self.assertRaises(asc_common.ApiError) as e:
            client.call("POST", "/profiles")
        self.assertEqual(e.exception.status, 500)
        self.assertEqual(session.request.call_count, 1)

    def test_network_error_becomes_api_error(self):
        client, session = self.retry_client(OSError("connection reset"))
        with self.assertRaises(asc_common.ApiError) as e:
            client.call("GET", "/apps")
        self.assertEqual(e.exception.status, 0)
        self.assertEqual(session.request.call_count, asc_common.Client.RETRIES + 1)
        self.assertNotIn("reset", str(e.exception))

    def test_metadata_locales(self):
        self.assertEqual(len(asc_common.metadata_locales()), 14)
        self.assertIn("en-US", asc_common.metadata_locales())


if __name__ == "__main__":
    unittest.main()

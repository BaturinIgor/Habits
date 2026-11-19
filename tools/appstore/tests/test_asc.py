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
            "other bundle": profile("P1", ident, bundle_db="B9"),
            "expiring": profile("P1", ident, expires=NOW + dt.timedelta(days=3)),
            "wrong id": profile("P1", APP + ".other"),
        }
        for name, p in cases.items():
            with self.subTest(name):
                self.assertEqual(prov.decide_profile([p], "B1", ident, "C1", GROUP, NOW), ("create", None, ["P1"]))

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

    def test_missing_gh_token_fails_before_apple(self):
        with mock.patch.object(prov, "gh_ready", return_value="нет токена"), \
                mock.patch.object(prov, "Client", side_effect=AssertionError("Apple не должен вызываться")), \
                redirect_stdout(io.StringIO()) as out, self.assertRaises(SystemExit):
            prov.main(["--store-secrets"])
        self.assertIn("GH_ADMIN_TOKEN", out.getvalue())

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
            self.assertEqual(c.writes(), [
                ("DELETE", "/appScreenshots/stale"), ("POST", "/appScreenshots"),
                ("PUT", "https://upload.example/x"), ("PATCH", "/appScreenshots/N1"),
                ("PATCH", "/appScreenshotSets/Sru/relationships/appScreenshots")])
            commit = [j for m, p, j, _ in c.calls if (m, p) == ("PATCH", "/appScreenshots/N1")][0]
            self.assertEqual(commit["data"]["attributes"], {"uploaded": True, "sourceFileChecksum": checksum})


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
        self.assertLess(len(text), 300)

    def test_metadata_locales(self):
        self.assertEqual(len(asc_common.metadata_locales()), 14)
        self.assertIn("en-US", asc_common.metadata_locales())


if __name__ == "__main__":
    unittest.main()

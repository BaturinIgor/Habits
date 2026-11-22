"""Тесты asc_offers: выбор цены −50% и план при уже заведённых предложениях (KAN-170, KAN-124)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import asc_offers as offers  # noqa: E402

TODAY = "2026-11-22"
POINTS = [("p0", "0.0"), ("p1", "5.99"), ("p2", "6.49"), ("p3", "6.99"), ("p4", "12.99")]


def price(terr, point, start=None, end=None, plan=None):
    attrs = {"startDate": start}
    if end:
        attrs["endDate"] = end
    if plan:
        attrs["planType"] = plan
    return {"id": f"{terr}-{point}", "attributes": attrs, "relationships": {
        "territory": {"data": {"id": terr}}, "subscriptionPricePoint": {"data": {"id": point}}}}


def custom(cid, expires, active=True, code="NEWYEAR2027"):
    return {"id": cid, "attributes": {"customCode": code, "expirationDate": expires, "active": active,
                                      "numberOfCodes": 10000}}


def nothing():
    return {"intro": {}, "promo": [], "codes": [], "custom": {}}


class HalfPoint(unittest.TestCase):
    def test_nearest_not_above_half(self):
        self.assertEqual(offers.half_point("12.99", POINTS), ("p2", "6.49"))

    def test_exact_half_is_allowed(self):
        self.assertEqual(offers.half_point("12.98", POINTS), ("p2", "6.49"))

    def test_never_free_and_none_when_too_cheap(self):
        self.assertIsNone(offers.half_point("0.99", POINTS))
        self.assertIsNone(offers.half_point(None, POINTS))

    def test_integer_currencies(self):
        pts = [("a", "499"), ("b", "549"), ("c", "599")]
        self.assertEqual(offers.half_point("1190", pts), ("b", "549"))


class CurrentPrices(unittest.TestCase):
    def test_takes_latest_started_upfront_price(self):
        prices = [price("USA", "old", "2025-01-01"), price("USA", "cur", "2026-06-01"),
                  price("USA", "future", "2027-01-01"), price("USA", "monthly", None, plan="MONTHLY"),
                  price("RUS", "r1", None), price("DEU", "ended", None, end="2026-01-01")]
        included = [{"type": "subscriptionPricePoints", "id": i, "attributes": {"customerPrice": c}}
                    for i, c in (("cur", "12.99"), ("r1", "1290.0"))]
        self.assertEqual(offers.current_prices(prices, included, TODAY),
                         {"USA": ("cur", "12.99"), "RUS": ("r1", "1290.0")})


class Plan(unittest.TestCase):
    terr = ["RUS", "USA"]
    yearly = {"USA": ("x", "12.99"), "RUS": ("y", "1299.0")}
    points = {"USA": POINTS, "RUS": [("r1", "599.0"), ("r2", "649.0"), ("r3", "699.0")]}

    def test_everything_missing(self):
        todo = offers.plan(self.terr, self.yearly, self.points, nothing())
        self.assertEqual(todo["intro"], ["RUS", "USA"])
        self.assertEqual(todo["promo"], {"USA": ("p2", "6.49"), "RUS": ("r2", "649.0")})
        self.assertEqual(todo["code"], todo["promo"])
        self.assertEqual(todo["custom"], "new")

    def test_all_created_means_empty_plan(self):
        existing = {
            "intro": {t: dict(offers.INTRO) for t in self.terr},
            "promo": [{"id": "PR1", "attributes": dict(offers.PROMO)}],
            "codes": [{"id": "OC1", "attributes": dict(offers.CODE)}],
            "custom": {"OC1": [custom("CC1", "2027-01-11")]},
        }
        todo = offers.plan(self.terr, self.yearly, None, existing)
        self.assertEqual((todo["intro"], todo["promo"], todo["code"], todo["custom"], todo["deactivate"]),
                         ([], None, None, None, []))
        self.assertEqual(todo["warnings"], [])

    def coded(self, *customs):
        existing = nothing()
        existing["codes"] = [{"id": "OC1", "attributes": dict(offers.CODE)}]
        existing["custom"] = {"OC1": list(customs)}
        return offers.plan(self.terr, self.yearly, None, existing)

    def test_old_expiration_is_replaced(self):
        # Дату у custom code поменять нельзя: новая партия до 11.01, старая (10.01) деактивируется.
        todo = self.coded(custom("666364", "2027-01-10T00:00:00-08:00"))
        self.assertEqual((todo["custom"], todo["deactivate"]), ("OC1", ["666364"]))

    def test_replaced_batch_after_partial_run(self):
        # Новая партия уже есть, старая ещё активна: только деактивировать.
        todo = self.coded(custom("666364", "2027-01-10"), custom("CC2", "2027-01-11"))
        self.assertEqual((todo["custom"], todo["deactivate"]), (None, ["666364"]))

    def test_replaced_batch_is_idempotent(self):
        todo = self.coded(custom("666364", "2027-01-10", active=False), custom("CC2", "2027-01-11"))
        self.assertEqual((todo["custom"], todo["deactivate"]), (None, []))

    def test_inactive_current_batch_is_recreated(self):
        todo = self.coded(custom("CC2", "2027-01-11", active=False))
        self.assertEqual((todo["custom"], todo["deactivate"]), ("OC1", []))

    def test_expiration_is_after_promo_end(self):
        # Акция в приложении идёт до 10.01 включительно, код истекает в 00:00 PT в день expirationDate.
        self.assertEqual(offers.CUSTOM_CODE["expirationDate"], "2027-01-11")

    def test_partial_intro_and_code_without_custom(self):
        existing = nothing()
        existing["intro"] = {"USA": dict(offers.INTRO),
                             "RUS": {"offerMode": "PAY_AS_YOU_GO", "duration": "ONE_MONTH", "numberOfPeriods": 1}}
        existing["codes"] = [{"id": "OC1", "attributes": dict(offers.CODE)}]
        todo = offers.plan(self.terr + ["DEU"], self.yearly, self.points, existing)
        self.assertEqual(todo["intro"], ["DEU"])
        self.assertEqual(todo["intro_conflicts"], ["RUS"])
        self.assertIsNone(todo["code"])
        self.assertEqual(todo["custom"], "OC1")
        self.assertEqual(todo["skipped"], ["DEU"])  # нет текущей цены yearly
        self.assertNotIn("DEU", todo["promo"])

    def test_other_offers_are_ignored(self):
        existing = nothing()
        existing["promo"] = [{"id": "X", "attributes": dict(offers.PROMO, offerCode="other")}]
        todo = offers.plan(self.terr, self.yearly, self.points, existing)
        self.assertEqual(len(todo["promo"]), 2)


class Payloads(unittest.TestCase):
    def test_offer_code_inline_prices(self):
        body = offers.offer_payload("code", "S1", {"USA": ("p2", "6.49"), "RUS": ("r2", "649.0")})
        data = body["data"]
        self.assertEqual(data["type"], "subscriptionOfferCodes")
        self.assertEqual(data["attributes"]["customerEligibilities"], ["NEW", "EXISTING", "EXPIRED"])
        self.assertEqual([r["id"] for r in data["relationships"]["prices"]["data"]], ["${p0}", "${p1}"])
        self.assertEqual(body["included"][0]["relationships"]["territory"]["data"]["id"], "RUS")
        self.assertEqual(body["included"][1]["relationships"]["subscriptionPricePoint"]["data"]["id"], "p2")

    def test_deactivate_only_active_flag(self):
        self.assertEqual(offers.deactivate_payload("666364"), {"data": {
            "type": "subscriptionOfferCodeCustomCodes", "id": "666364", "attributes": {"active": False}}})

    def test_custom_code_new_expiration(self):
        attrs = offers.custom_code_payload("OC1")["data"]["attributes"]
        self.assertEqual(attrs, {"customCode": "NEWYEAR2027", "numberOfCodes": 10000,
                                 "expirationDate": "2027-01-11"})

    def test_values_match_app(self):
        root = os.path.join(os.path.dirname(__file__), "..", "..", "..")
        path = os.path.join(root, "Habits/Features/NewYearOffer.swift")
        if not os.path.exists(path):
            self.skipTest("NewYearOffer.swift ещё не в этой ветке")
        swift = open(path, encoding="utf-8").read()
        self.assertIn(f'"{offers.PROMO["offerCode"]}"', swift)
        self.assertIn(f'"{offers.CUSTOM_CODE["customCode"]}"', swift)
        self.assertIn("discountPercent = 50", swift)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Предложения годовой подписки Pro в App Store Connect (KAN-170, KAN-124). Идемпотентно.

Шаги (по умолчанию все):
- prices — только читает: есть ли цены у monthly, yearly и lifetime во всех территориях продажи;
- intro  — бесплатная неделя (FREE_TRIAL, ONE_WEEK) для новых подписчиков в каждой территории yearly;
- promo  — promotional offer `newyear2027`: PAY_UP_FRONT, ONE_YEAR, цена ≈ −50%. Приложение только
           читает его цену (Habits/Features/NewYearOffer.swift, priceOfferID);
- code   — offer code `NEWYEAR2027` с теми же ценами, для new/existing/expired, custom code
           `NEWYEAR2027` до 10.01.2027.

Цена со скидкой в каждой территории — ближайшая price point не выше половины текущей цены yearly.
Повторный запуск ничего не дублирует: то, что уже заведено, пропускается.
Репозиторий публичный: печатаем только ID, статусы, цены, HTTP-коды и коды ошибок Apple.

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APP_BUNDLE_ID.

    python3 tools/appstore/asc_offers.py --dry-run
    python3 tools/appstore/asc_offers.py --apply --steps intro,promo,code
"""
import argparse
import datetime as dt
import os
import sys
from decimal import Decimal, InvalidOperation

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import API, DEFAULT_BUNDLE_ID, ApiError, Client, find_app  # noqa: E402

API_V2 = API.replace("/v1", "/v2")

STEPS = ("prices", "intro", "promo", "code")

# Должно совпадать с Habits/Features/NewYearOffer.swift и HabitsTests/Habits.storekit.
INTRO = {"offerMode": "FREE_TRIAL", "duration": "ONE_WEEK", "numberOfPeriods": 1}
PROMO = {"offerCode": "newyear2027", "name": "New Year 2027 price",
         "offerMode": "PAY_UP_FRONT", "duration": "ONE_YEAR", "numberOfPeriods": 1}
CODE = {"name": "NEWYEAR2027", "customerEligibilities": ["NEW", "EXISTING", "EXPIRED"],
        "offerEligibility": "STACK_WITH_INTRO_OFFERS",
        "offerMode": "PAY_UP_FRONT", "duration": "ONE_YEAR", "numberOfPeriods": 1}
CUSTOM_CODE = {"customCode": "NEWYEAR2027", "numberOfCodes": 10000, "expirationDate": "2027-01-10"}
DISCOUNT = Decimal("0.5")
KEY_TERRITORIES = ("USA", "RUS", "DEU", "FRA", "GBR", "JPN", "IND", "BRA")


# ---------- чистая логика (юнит-тесты) ----------

def dec(value):
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError):
        return None


def half_point(current_price, points):
    """Ближайшая price point не выше половины текущей цены (бесплатную не берём).
    points: [(id, customerPrice)]. Возвращает (id, цена) или None."""
    target = dec(current_price)
    if target is None:
        return None
    target *= DISCOUNT
    best = None
    for pid, price in points:
        p = dec(price)
        if p is None or p <= 0 or p > target:
            continue
        if best is None or p > best[1]:
            best = (pid, p)
    return (best[0], str(best[1])) if best else None


def current_prices(prices, included, today):
    """{территория: (price_point_id, customerPrice)} из ответа /subscriptions/{id}/prices или
    цен покупки: действующая сейчас цена (startDate не позже сегодня, endDate позже), самая свежая."""
    points = {i["id"]: (i.get("attributes") or {}).get("customerPrice")
              for i in included if i["type"] in ("subscriptionPricePoints", "inAppPurchasePricePoints")}
    best = {}
    for p in prices:
        a = p.get("attributes") or {}
        if a.get("planType") not in (None, "UPFRONT"):
            continue
        start, end = a.get("startDate"), a.get("endDate")
        if (start and start > today) or (end and end <= today):
            continue
        rel = p.get("relationships") or {}
        terr = ((rel.get("territory") or {}).get("data") or {}).get("id")
        point = (((rel.get("subscriptionPricePoint") or rel.get("inAppPurchasePricePoint") or {})
                  .get("data")) or {}).get("id")
        if not terr or not point:
            continue
        if terr not in best or (start or "") >= best[terr][0]:
            best[terr] = (start or "", point, points.get(point))
    return {t: (v[1], v[2]) for t, v in best.items()}


def intro_territories(intro_offers, today):
    """{территория: attributes} действующих или будущих вводных предложений."""
    result = {}
    for o in intro_offers:
        a = o.get("attributes") or {}
        if a.get("endDate") and a["endDate"] < today:
            continue
        terr = (((o.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")
        if terr:
            result[terr] = a
    return result


def same_offer(attrs, want):
    return all(attrs.get(k) == v for k, v in want.items() if k not in ("name", "offerCode",
                                                                      "customerEligibilities"))


def plan(territories, yearly_prices, points_by_territory, existing):
    """Что нужно создать. existing: {"intro": {терр: attrs}, "promo": [offers], "codes": [offers],
    "custom": {offer_code_id: [custom codes]}}. points_by_territory: {терр: [(id, price)]} или None,
    если цены точек не загружались (тогда цены в плане не считаются).
    Возвращает dict шагов: intro=[терр], intro_conflicts=[терр], promo/code=None|{терр: (id, цена)},
    custom=None|offer_code_id|"new", skipped=[терр без цены], warnings=[...]."""
    result = {"intro": [], "intro_conflicts": [], "promo": None, "code": None, "custom": None,
              "skipped": [], "warnings": []}
    for t in sorted(territories):
        attrs = existing["intro"].get(t)
        if attrs is None:
            result["intro"].append(t)
        elif not same_offer(attrs, INTRO):
            result["intro_conflicts"].append(t)

    promo = [o for o in existing["promo"] if (o.get("attributes") or {}).get("offerCode") == PROMO["offerCode"]]
    codes = [o for o in existing["codes"] if (o.get("attributes") or {}).get("name") == CODE["name"]]
    for kind, found, want in (("promo", promo, PROMO), ("code", codes, CODE)):
        for o in found:
            if not same_offer(o.get("attributes") or {}, want):
                result["warnings"].append(f"{kind} {o['id']} уже есть, но с другими условиями: не трогаю")
    need_prices = not promo or not codes
    discounted = {}
    if need_prices and points_by_territory is not None:
        for t in sorted(territories):
            cur = yearly_prices.get(t)
            pick = half_point(cur[1], points_by_territory.get(t, [])) if cur else None
            if pick:
                discounted[t] = pick
            else:
                result["skipped"].append(t)
    if not promo:
        result["promo"] = discounted
    if not codes:
        result["code"] = discounted
        result["custom"] = "new"
    else:
        code_id = codes[0]["id"]
        customs = [c for c in existing["custom"].get(code_id, [])
                   if (c.get("attributes") or {}).get("customCode") == CUSTOM_CODE["customCode"]]
        if not customs:
            result["custom"] = code_id
    return result


def offer_payload(kind, subscription_id, prices):
    """Тело POST для promotional offer или offer code с ценами по территориям (inline)."""
    if kind == "promo":
        rtype, ptype, attrs = "subscriptionPromotionalOffers", "subscriptionPromotionalOfferPrices", dict(PROMO)
    else:
        rtype, ptype, attrs = "subscriptionOfferCodes", "subscriptionOfferCodePrices", dict(CODE)
    refs, included = [], []
    for i, (terr, (point_id, _price)) in enumerate(sorted(prices.items())):
        local = f"${{p{i}}}"
        refs.append({"type": ptype, "id": local})
        included.append({"type": ptype, "id": local, "relationships": {
            "territory": {"data": {"type": "territories", "id": terr}},
            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point_id}}}})
    return {"data": {"type": rtype, "attributes": attrs, "relationships": {
        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
        "prices": {"data": refs}}}, "included": included}


def intro_payload(subscription_id, territory):
    return {"data": {"type": "subscriptionIntroductoryOffers", "attributes": dict(INTRO), "relationships": {
        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
        "territory": {"data": {"type": "territories", "id": territory}}}}}


def custom_code_payload(offer_code_id):
    return {"data": {"type": "subscriptionOfferCodeCustomCodes", "attributes": dict(CUSTOM_CODE),
                     "relationships": {"offerCode": {"data": {"type": "subscriptionOfferCodes",
                                                              "id": offer_code_id}}}}}


# ---------- чтение App Store Connect ----------

def find_products(client, app_id):
    subs = {}
    for g in client.get_all(f"/apps/{app_id}/subscriptionGroups")[0]:
        for s in client.get_all(f"/subscriptionGroups/{g['id']}/subscriptions")[0]:
            subs[s["attributes"].get("productId", "")] = s
    iaps = {i["attributes"].get("productId", ""): i for i in client.get_all(f"/apps/{app_id}/inAppPurchasesV2")[0]}

    def pick(items, suffix):
        found = [v for k, v in items.items() if k.endswith(suffix)]
        return found[0] if found else None
    return pick(subs, ".pro.monthly"), pick(subs, ".pro.yearly"), pick(iaps, ".pro.lifetime")


def territories_of(client, path_availability, path_territories, label):
    """Территории продажи из availability. None, если availability не задана."""
    try:
        avail = client.call("GET", path_availability).get("data")
    except ApiError as e:
        if e.status == 404:
            avail = None
        else:
            raise
    if not avail:
        print(f"  {label}: availability не задана")
        return None, None
    terr = client.get_all(path_territories.format(id=avail["id"]))[0]
    return {t["id"] for t in terr}, avail


def territory_currency(client):
    return {t["id"]: (t.get("attributes") or {}).get("currency", "")
            for t in client.get_all("/territories")[0]}


def subscription_prices(client, sub_id, today):
    data, inc = client.get_all(f"/subscriptions/{sub_id}/prices",
                               {"include": "subscriptionPricePoint,territory"})
    return current_prices(data, inc, today)


def lifetime_prices(client, iap_id, today):
    sched = client.call("GET", f"{API_V2}/inAppPurchases/{iap_id}/iapPriceSchedule").get("data")
    if not sched:
        return {}
    result = {}
    for kind in ("manualPrices", "automaticPrices"):
        data, inc = client.get_all(f"/inAppPurchasePriceSchedules/{sched['id']}/{kind}",
                                   {"include": "inAppPurchasePricePoint,territory"})
        for t, v in current_prices(data, inc, today).items():
            if kind == "manualPrices" or t not in result:
                result[t] = v
    return result


def price_points(client, sub_id, territory):
    data, _ = client.get_all(f"/subscriptions/{sub_id}/pricePoints",
                             {"filter[territory]": territory, "limit": 8000,
                              "fields[subscriptionPricePoints]": "customerPrice"})
    return [(p["id"], (p.get("attributes") or {}).get("customerPrice")) for p in data]


def fmt(terr, price, currency):
    return f"{terr} {price} {currency.get(terr, '')}".strip()


# ---------- main ----------

def check_prices(client, products, today, currency):
    """Сводка: где у трёх товаров нет цены. Возвращает (territories, prices) для yearly."""
    monthly, yearly, lifetime = products
    print("== Цены во всех территориях продажи")
    out = {}
    for label, item, kind in (("monthly", monthly, "sub"), ("yearly", yearly, "sub"), ("lifetime", lifetime, "iap")):
        if not item:
            print(f"  ✗ {label}: товар не найден")
            continue
        state = item["attributes"].get("state")
        if kind == "sub":
            terr, _ = territories_of(client, f"/subscriptions/{item['id']}/subscriptionAvailability",
                                     "/subscriptionAvailabilities/{id}/availableTerritories", label)
            prices = subscription_prices(client, item["id"], today)
        else:
            terr, _ = territories_of(
                client, f"{API_V2}/inAppPurchases/{item['id']}/inAppPurchaseAvailability",
                "/inAppPurchaseAvailabilities/{id}/availableTerritories", label)
            prices = lifetime_prices(client, item["id"], today)
        if terr is None:
            terr = set(prices)
        missing = sorted(terr - set(prices))
        key = ", ".join(fmt(t, prices[t][1], currency) for t in KEY_TERRITORIES if t in prices)
        print(f"  {label} {item['attributes'].get('productId')} ({item['id']}, {state}): "
              f"территорий продажи {len(terr)}, с ценой {len(set(prices) & terr)}")
        print(f"    ключевые: {key}")
        if missing:
            print(f"  ✗ {label}: нет цены в {len(missing)} территориях: {', '.join(missing)}")
        else:
            print(f"  ✓ {label}: цены заданы во всех территориях продажи")
        out[label] = (terr, prices)
    return out.get("yearly")


def main():
    p = argparse.ArgumentParser()
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    p.add_argument("--steps", default=",".join(STEPS))
    args = p.parse_args()
    steps = {s.strip() for s in args.steps.split(",") if s.strip()}
    if steps - set(STEPS):
        raise SystemExit(f"::error::неизвестные шаги: {', '.join(sorted(steps - set(STEPS)))}")
    steps.add("prices")

    client = Client()
    today = dt.date.today().isoformat()
    app = find_app(client, os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID)
    products = find_products(client, app["id"])
    yearly = products[1]
    if not yearly:
        raise SystemExit("::error::подписка .pro.yearly не найдена")
    currency = territory_currency(client)
    terr, yearly_prices = check_prices(client, products, today, currency) or (set(), {})
    territories = sorted(terr & set(yearly_prices))
    sid = yearly["id"]
    print(f"== Pro Yearly {sid}: state {yearly['attributes'].get('state')}, территорий для предложений {len(territories)}")

    existing = {
        "intro": intro_territories(client.get_all(f"/subscriptions/{sid}/introductoryOffers",
                                                  {"include": "territory"})[0], today),
        "promo": client.get_all(f"/subscriptions/{sid}/promotionalOffers")[0],
        "codes": client.get_all(f"/subscriptions/{sid}/offerCodes")[0],
        "custom": {},
    }
    for o in existing["codes"]:
        existing["custom"][o["id"]] = client.get_all(f"/subscriptionOfferCodes/{o['id']}/customCodes")[0]
    for o in existing["promo"]:
        print(f"  есть promotional offer {o['id']}: {o['attributes'].get('offerCode')}")
    for o in existing["codes"]:
        a = o["attributes"]
        print(f"  есть offer code {o['id']}: {a.get('name')}, active={a.get('active')}, "
              f"custom: {[c['attributes'].get('customCode') for c in existing['custom'][o['id']]]}")

    pre = plan(territories, yearly_prices, None, existing)
    need_points = (("promo" in steps and pre["promo"] is not None) or ("code" in steps and pre["code"] is not None))
    points = None
    if need_points:
        print(f"  загружаю price points для {len(territories)} территорий…")
        points = {t: price_points(client, sid, t) for t in territories}
    todo = plan(territories, yearly_prices, points, existing)

    print("== План")
    for w in todo["warnings"]:
        print(f"::warning::{w}")
    if "intro" in steps:
        print(f"  intro: создать в {len(todo['intro'])} территориях" + (f": {', '.join(todo['intro'])}" if todo["intro"] else ""))
        if todo["intro_conflicts"]:
            print(f"::warning::intro: в {len(todo['intro_conflicts'])} территориях уже другое вводное предложение, "
                  f"не трогаю: {', '.join(todo['intro_conflicts'])}")
    if todo["skipped"] and need_points:
        print(f"::warning::нет подходящей price point (−50%) в: {', '.join(todo['skipped'])}")
    for kind in ("promo", "code"):
        if kind not in steps:
            continue
        prices = todo[kind]
        if prices is None:
            print(f"  {kind}: уже есть")
            continue
        print(f"  {kind}: создать с ценами в {len(prices)} территориях")
        for t in sorted(prices):
            print(f"    {t}: {yearly_prices[t][1]} -> {prices[t][1]} {currency.get(t, '')}")
    if "code" in steps:
        if todo["custom"] is None:
            print(f"  custom code {CUSTOM_CODE['customCode']}: уже есть")
        else:
            print(f"  custom code {CUSTOM_CODE['customCode']}: создать ({CUSTOM_CODE['numberOfCodes']} погашений, "
                  f"до {CUSTOM_CODE['expirationDate']})")
    nothing = (("intro" not in steps or not todo["intro"]) and ("promo" not in steps or todo["promo"] is None)
               and ("code" not in steps or (todo["code"] is None and todo["custom"] is None)))
    if nothing:
        print("ИТОГ: план пустой, всё уже заведено")
    if args.dry_run or nothing:
        return

    errors = []

    def attempt(label, fn):
        try:
            return fn()
        except ApiError as e:
            errors.append(f"{label}: {e}")
            print(f"  ✗ {label}: {e}")
            return None

    print("== Создаю")
    if "intro" in steps:
        made = 0
        for t in todo["intro"]:
            if attempt(f"intro {t}", lambda t=t: client.call("POST", "/subscriptionIntroductoryOffers",
                                                              json=intro_payload(sid, t))) is not None:
                made += 1
        print(f"  intro: создано {made} из {len(todo['intro'])}")
    if "promo" in steps and todo["promo"]:
        r = attempt("promo", lambda: client.call("POST", "/subscriptionPromotionalOffers",
                                                 json=offer_payload("promo", sid, todo["promo"])))
        if r:
            print(f"  ✓ promotional offer {r['data']['id']} ({PROMO['offerCode']})")
    if "code" in steps:
        code_id = todo["custom"] if todo["custom"] not in (None, "new") else None
        if todo["code"]:
            r = attempt("offer code", lambda: client.call("POST", "/subscriptionOfferCodes",
                                                          json=offer_payload("code", sid, todo["code"])))
            if r:
                code_id = r["data"]["id"]
                print(f"  ✓ offer code {code_id} ({CODE['name']})")
        if code_id:
            r = attempt("custom code", lambda: client.call("POST", "/subscriptionOfferCodeCustomCodes",
                                                           json=custom_code_payload(code_id)))
            if r:
                print(f"  ✓ custom code {r['data']['id']} ({CUSTOM_CODE['customCode']})")
    if errors:
        for e in errors:
            print(f"::error::{e}")
        sys.exit(1)
    print("ИТОГ: создано, повтори dry_run для проверки")


if __name__ == "__main__":
    main()

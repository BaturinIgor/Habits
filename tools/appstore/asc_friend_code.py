#!/usr/bin/env python3
"""Offer code «Пригласи друга» (KAN-228): месяц Pro бесплатно на месячной подписке. Идемпотентно.

- offer code `FRIEND2027`: FREE_TRIAL, ONE_MONTH, только новые подписчики, во всех территориях
  продажи месячной подписки;
- custom code `FRIEND2027` (его показывает экран Habits/Views/Settings/InviteFriendView.swift)
  на FRIEND_CUSTOM["numberOfCodes"] погашений до FRIEND_CUSTOM["expirationDate"].

Повторный запуск ничего не дублирует. Репозиторий публичный: печатаем только ID, статусы, HTTP-коды
и коды ошибок Apple.

    python3 tools/appstore/asc_friend_code.py --dry-run
    python3 tools/appstore/asc_friend_code.py --apply
"""
import argparse
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_common import DEFAULT_BUNDLE_ID, ApiError, Client, find_app  # noqa: E402
from asc_offers import find_products, subscription_prices, territories_of  # noqa: E402

# Должно совпадать с FriendInvite.code в InviteFriendView.swift.
FRIEND_CODE = {"name": "FRIEND2027", "customerEligibilities": ["NEW"],
               "offerEligibility": "REPLACE_INTRO_OFFERS",
               "offerMode": "FREE_TRIAL", "duration": "ONE_MONTH", "numberOfPeriods": 1}
FRIEND_CUSTOM = {"customCode": "FRIEND2027", "numberOfCodes": 10000, "expirationDate": "2027-12-31"}


def code_payload(subscription_id, prices, with_price_points):
    """Тело POST /subscriptionOfferCodes. prices: {территория: (price point id, цена)}.
    Для бесплатного месяца Apple может принять территорию без price point; если нет, шлём текущую цену."""
    refs, included = [], []
    for i, (terr, (point_id, _)) in enumerate(sorted(prices.items())):
        local = f"${{f{i}}}"
        rel = {"territory": {"data": {"type": "territories", "id": terr}}}
        if with_price_points:
            rel["subscriptionPricePoint"] = {"data": {"type": "subscriptionPricePoints", "id": point_id}}
        refs.append({"type": "subscriptionOfferCodePrices", "id": local})
        included.append({"type": "subscriptionOfferCodePrices", "id": local, "relationships": rel})
    return {"data": {"type": "subscriptionOfferCodes", "attributes": dict(FRIEND_CODE), "relationships": {
        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
        "prices": {"data": refs}}}, "included": included}


def custom_payload(offer_code_id):
    return {"data": {"type": "subscriptionOfferCodeCustomCodes", "attributes": dict(FRIEND_CUSTOM),
                     "relationships": {"offerCode": {"data": {"type": "subscriptionOfferCodes",
                                                              "id": offer_code_id}}}}}


def main():
    p = argparse.ArgumentParser()
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = p.parse_args()

    client = Client()
    app = find_app(client, os.environ.get("APP_BUNDLE_ID") or DEFAULT_BUNDLE_ID)
    monthly = find_products(client, app["id"])[0]
    if not monthly:
        raise SystemExit("::error::подписка .pro.monthly не найдена")
    mid = monthly["id"]
    terr, _ = territories_of(client, f"/subscriptions/{mid}/subscriptionAvailability",
                             "/subscriptionAvailabilities/{id}/availableTerritories", "monthly")
    prices = subscription_prices(client, mid, dt.date.today().isoformat())
    prices = {t: v for t, v in prices.items() if terr is None or t in terr}
    print(f"== Pro Monthly {mid}: state {monthly['attributes'].get('state')}, территорий с ценой {len(prices)}")

    codes = [o for o in client.get_all(f"/subscriptions/{mid}/offerCodes")[0]
             if (o.get("attributes") or {}).get("name") == FRIEND_CODE["name"]]
    code_id = codes[0]["id"] if codes else None
    customs = []
    if code_id:
        customs = [c for c in client.get_all(f"/subscriptionOfferCodes/{code_id}/customCodes")[0]
                   if (c.get("attributes") or {}).get("customCode") == FRIEND_CUSTOM["customCode"]
                   and (c.get("attributes") or {}).get("active") is not False]
        print(f"  есть offer code {code_id}: active={codes[0]['attributes'].get('active')}, "
              f"custom: {[(c['id'], (c['attributes'].get('expirationDate') or '')[:10]) for c in customs]}")

    print("== План")
    print(f"  offer code {FRIEND_CODE['name']}: " + ("уже есть" if code_id else f"создать в {len(prices)} территориях"))
    print(f"  custom code {FRIEND_CUSTOM['customCode']}: " + ("уже есть" if customs else
          f"создать ({FRIEND_CUSTOM['numberOfCodes']} погашений, до {FRIEND_CUSTOM['expirationDate']})"))
    if code_id and customs:
        print("ИТОГ: план пустой, всё уже заведено")
        return
    if args.dry_run:
        return

    print("== Создаю")
    if not code_id:
        try:
            r = client.call("POST", "/subscriptionOfferCodes", json=code_payload(mid, prices, False))
        except ApiError as e:
            # Повторяем только при отказе по содержимому запроса. При 401/429/5xx код мог уже создаться,
            # и повтор упал бы на дубликате имени; такой запуск честно падает, перезапуск найдёт код по имени.
            if e.status not in (400, 409, 422):
                raise
            print(f"  без price point не принято ({e}); повторяю с текущими ценами")
            r = client.call("POST", "/subscriptionOfferCodes", json=code_payload(mid, prices, True))
        code_id = r["data"]["id"]
        print(f"  ✓ offer code {code_id} ({FRIEND_CODE['name']})")
    r = client.call("POST", "/subscriptionOfferCodeCustomCodes", json=custom_payload(code_id))
    print(f"  ✓ custom code {r['data']['id']} ({FRIEND_CUSTOM['customCode']}, до {FRIEND_CUSTOM['expirationDate']})")
    print("ИТОГ: готово")


if __name__ == "__main__":
    main()

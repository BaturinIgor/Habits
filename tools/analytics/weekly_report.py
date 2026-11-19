#!/usr/bin/env python3
"""Еженедельный отчёт ZenHab: продажи и подписки из App Store Connect за последние 7 дней.

Скачивает дневные отчёты Sales and Trends (SALES/SUMMARY, SUBSCRIPTION, SUBSCRIPTION_EVENT),
сравнивает с предыдущей неделей и пишет:
- <REPORT_DIR>/<дата>.md  — отчёт для чтения;
- <REPORT_DIR>/<дата>.json — те же цифры для машин;
- короткое сообщение в Telegram (бот отзывов), если заданы FEEDBACK_BOT_TOKEN и FEEDBACK_CHAT_ID.

Репозиторий публичный: цифры дохода не печатаются в лог (логи Actions видны всем) и не коммитятся,
workflow хранит файлы только артефактом запуска на короткий срок.

Поведение в приложении (экраны, нажатия, воронка) смотрим в Firebase / Google Analytics.
Позже сюда можно добавить и их через бесплатный Google Analytics Data API (нужен сервисный аккаунт).

Переменные окружения: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (текст .p8 или base64), ASC_VENDOR_NUMBER.
Необязательно: REPORT_DIR (по умолчанию reports/weekly), FEEDBACK_BOT_TOKEN, FEEDBACK_CHAT_ID.
"""
import base64
import csv
import datetime as dt
import gzip
import io
import json
import os
import sys
import time
from collections import Counter, defaultdict

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1/salesReports"

DOWNLOADS = {"1", "1F", "1T", "1E", "1EP", "1EU", "F1"}
REDOWNLOADS = {"3", "3F", "3T", "F3"}
UPDATES = {"7", "7F", "7T", "F7"}


REQUIRED = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "ASC_VENDOR_NUMBER")


def token():
    key = os.environ["ASC_KEY_P8"].strip()
    if "BEGIN PRIVATE KEY" not in key:
        try:
            key = base64.b64decode(key, validate=True).decode()
        except ValueError:
            fail("ASC_KEY_P8 должен быть текстом .p8 (-----BEGIN PRIVATE KEY-----...) или его base64.")
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


# Сессия создаётся в main(), после проверки секретов: иначе без них скрипт падал бы с KeyError при импорте.
SESSION = requests.Session()
VENDOR = ""


def get_with_retry(params, attempts=3):
    """GET к App Store Connect с повтором при сетевых ошибках и 5xx. None, если так и не ответил."""
    for attempt in range(attempts):
        try:
            r = SESSION.get(API, params=params, timeout=60)
        except requests.RequestException as error:
            # Только тип ошибки: в тексте мог бы оказаться адрес запроса.
            print(f"::warning::Сеть ({type(error).__name__}), попытка {attempt + 1} из {attempts}")
        else:
            if r.status_code < 500:
                return r
            print(f"::warning::App Store Connect ответил {r.status_code}, попытка {attempt + 1} из {attempts}")
        if attempt + 1 < attempts:
            time.sleep(5 * (attempt + 1))
    return None


def fetch(report_type, sub_type, day, versions):
    """Строки дневного отчёта или None, если отчёта за этот день ещё нет."""
    for version in versions:
        params = {
            "filter[frequency]": "DAILY",
            "filter[reportType]": report_type,
            "filter[reportSubType]": sub_type,
            "filter[vendorNumber]": VENDOR,
            "filter[reportDate]": day.isoformat(),
            "filter[version]": version,
        }
        r = get_with_retry(params)
        if r is None:
            print(f"::warning::{report_type}/{sub_type} {day}: App Store Connect не отвечает")
            return None
        if r.status_code == 200:
            raw = r.content
            try:
                raw = gzip.decompress(raw)
            except OSError:
                pass
            text = raw.decode("utf-8-sig")
            return list(csv.DictReader(io.StringIO(text), delimiter="\t"))
        if r.status_code == 404:
            return None
        body = r.text[:400]
        # Неподходящая версия отчёта: пробуем следующую.
        if r.status_code == 400 and "version" in body.lower():
            continue
        if r.status_code in (401, 403):
            print(f"::error::Нет доступа к отчётам продаж ({r.status_code}). Ключу API нужна роль Sales, Finance или Admin. {body}")
            sys.exit(1)
        print(f"::warning::{report_type}/{sub_type} {day}: {r.status_code} {body}")
        return None
    print(f"::warning::{report_type}/{sub_type}: ни одна версия отчёта не подошла ({versions})")
    return None


def num(value):
    try:
        return float(str(value).replace(",", "") or 0)
    except ValueError:
        return 0.0


def summarize_sales(rows_by_day):
    s = {"downloads": 0, "redownloads": 0, "updates": 0, "iap_units": 0, "refunds": 0,
         "proceeds": defaultdict(float), "countries": Counter(), "products": Counter()}
    for rows in rows_by_day:
        for row in rows or []:
            kind = row.get("Product Type Identifier", "")
            units = int(num(row.get("Units")))
            if kind in DOWNLOADS:
                s["downloads"] += units
                s["countries"][row.get("Country Code", "?")] += units
            elif kind in REDOWNLOADS:
                s["redownloads"] += units
            elif kind in UPDATES:
                s["updates"] += units
            elif kind.startswith("IA") or kind.startswith("FI"):
                if units < 0:
                    s["refunds"] += -units
                else:
                    s["iap_units"] += units
                s["products"][row.get("SKU", "?")] += units
            proceeds = num(row.get("Developer Proceeds")) * units
            if proceeds:
                s["proceeds"][row.get("Currency of Proceeds", "?")] += proceeds
    s["proceeds"] = {k: round(v, 2) for k, v in s["proceeds"].items()}
    s["countries"] = dict(s["countries"].most_common(10))
    s["products"] = dict(s["products"])
    return s


def summarize_events(rows_by_day):
    events = Counter()
    for rows in rows_by_day:
        for row in rows or []:
            events[row.get("Event", "?")] += int(num(row.get("Quantity", 1)) or 1)
    return dict(events.most_common())


def summarize_active(rows):
    """Снимок активных подписок за последний доступный день."""
    total = Counter()
    for row in rows or []:
        for key, value in row.items():
            if key and key.startswith("Active ") or key in ("Billing Retry", "Grace Period", "Subscribers"):
                total[key] += int(num(value))
    return dict(total)


def collect(days):
    sales, events = [], []
    for day in days:
        sales.append(fetch("SALES", "SUMMARY", day, ["1_1", "1_0"]))
        events.append(fetch("SUBSCRIPTION_EVENT", "SUMMARY", day, ["1_4", "1_3", "1_2"]))
    return summarize_sales(sales), summarize_events(events)


def available_days(today):
    """7 последних дней, за которые Apple уже выложила отчёт (обычно до позавчера)."""
    end = today - dt.timedelta(days=1)
    for _ in range(4):
        if fetch("SALES", "SUMMARY", end, ["1_1", "1_0"]) is not None:
            break
        end -= dt.timedelta(days=1)
    return [end - dt.timedelta(days=i) for i in range(6, -1, -1)]


def delta(now, before):
    if before == 0:
        return "" if now == 0 else " (новое)"
    change = (now - before) / before * 100
    return f" ({'+' if change >= 0 else ''}{change:.0f}% к прошлой неделе)"


def main():
    global VENDOR
    missing = [name for name in REQUIRED if not os.environ.get(name, "").strip()]
    if missing:
        hint = " ASC_VENDOR_NUMBER видно в App Store Connect: Payments and Financial Reports, слева вверху." \
            if "ASC_VENDOR_NUMBER" in missing else ""
        fail("Не заданы секреты: " + ", ".join(missing) + "." + hint)
    VENDOR = os.environ["ASC_VENDOR_NUMBER"].strip()
    try:
        SESSION.headers.update({"Authorization": f"Bearer {token()}"})
    except (ValueError, TypeError, jwt.PyJWTError) as error:
        fail(f"Не удалось подписать токен App Store Connect ключом ASC_KEY_P8 ({type(error).__name__}). Проверьте ключ.")
    today = dt.date.today()
    week = available_days(today)
    prev = [d - dt.timedelta(days=7) for d in week]
    sales, events = collect(week)
    prev_sales, prev_events = collect(prev)
    active = {}
    for day in reversed(week):
        rows = fetch("SUBSCRIPTION", "SUMMARY", day, ["1_4", "1_3", "1_2"])
        if rows is not None:
            active = summarize_active(rows)
            break

    period = f"{week[0].isoformat()} — {week[-1].isoformat()}"
    lines = [f"# ZenHab: неделя {period}", ""]
    lines += ["## App Store", ""]
    lines.append(f"- Установки: **{sales['downloads']}**{delta(sales['downloads'], prev_sales['downloads'])}")
    lines.append(f"- Повторные загрузки: {sales['redownloads']}")
    lines.append(f"- Обновления: {sales['updates']}")
    lines.append(f"- Покупки (подписки и навсегда): **{sales['iap_units']}**{delta(sales['iap_units'], prev_sales['iap_units'])}")
    if sales["refunds"]:
        lines.append(f"- Возвраты: {sales['refunds']}")
    proceeds = ", ".join(f"{v:.2f} {k}" for k, v in sales["proceeds"].items()) or "0"
    lines.append(f"- Доход разработчика: **{proceeds}**")
    if sales["products"]:
        lines.append("- По продуктам: " + ", ".join(f"{k} {v}" for k, v in sales["products"].items()))
    if sales["countries"]:
        lines.append("- Установки по странам: " + ", ".join(f"{k} {v}" for k, v in sales["countries"].items()))
    lines += ["", "## Подписки", ""]
    if events:
        for name, count in events.items():
            before = prev_events.get(name, 0)
            lines.append(f"- {name}: {count} (неделей раньше {before})")
    else:
        lines.append("- Событий подписок за неделю нет.")
    if active:
        lines += ["", "Активные подписки на " + week[-1].isoformat() + ":"]
        for name, count in active.items():
            lines.append(f"- {name}: {count}")
    lines += ["", "## Поведение в приложении", "",
              "Экраны, нажатия, воронка пейвола и удержание: Firebase → Analytics (события screen_view, paywall_shown, purchase_*).", ""]
    report = "\n".join(lines)
    # Сам отчёт в лог не печатаем: логи публичного репозитория видны всем.
    print(f"Отчёт за {period} готов.")

    out_dir = os.environ.get("REPORT_DIR", "reports/weekly")
    os.makedirs(out_dir, exist_ok=True)
    name = week[-1].isoformat()
    with open(os.path.join(out_dir, name + ".md"), "w", encoding="utf-8") as f:
        f.write(report)
    with open(os.path.join(out_dir, name + ".json"), "w", encoding="utf-8") as f:
        json.dump({"period": [week[0].isoformat(), week[-1].isoformat()], "sales": sales, "previousSales": prev_sales,
                   "subscriptionEvents": events, "previousSubscriptionEvents": prev_events,
                   "activeSubscriptions": active}, f, ensure_ascii=False, indent=2)

    bot, chat = os.environ.get("FEEDBACK_BOT_TOKEN"), os.environ.get("FEEDBACK_CHAT_ID")
    if bot and chat:
        short = [f"ZenHab, неделя {period}",
                 f"Установки: {sales['downloads']}{delta(sales['downloads'], prev_sales['downloads'])}",
                 f"Покупки: {sales['iap_units']}{delta(sales['iap_units'], prev_sales['iap_units'])}",
                 f"Доход: {proceeds}"]
        trials = sum(v for k, v in events.items() if "Introductory" in k or "Free Trial" in k)
        if trials:
            short.append(f"Пробные периоды и переходы из них: {trials}")
        try:
            r = requests.post(f"https://api.telegram.org/bot{bot}/sendMessage",
                              data={"chat_id": chat, "text": "\n".join(short)}, timeout=30)
        except requests.RequestException as error:
            # Только тип ошибки: в тексте исключения есть адрес с токеном бота.
            print(f"::warning::Telegram недоступен ({type(error).__name__})")
        else:
            if r.status_code != 200:
                print(f"::warning::Telegram: {r.status_code}")
            else:
                print("Сводка отправлена в Telegram.")


if __name__ == "__main__":
    main()

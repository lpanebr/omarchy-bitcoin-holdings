"""Consulta pública reproduzível; não recebe quantidade ou configuração pessoal."""
import calendar
import datetime as dt
import json
import time
import urllib.parse
import urllib.request


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "BitcoinHoldings-validation/0.1"}), timeout=20) as response:
        return json.load(response)


def beginning(now, period):
    if period == "week":
        return now - dt.timedelta(days=7)
    year, month = now.year, now.month
    if period == "month":
        month -= 1
        if not month:
            year, month = year - 1, 12
    else:
        year -= 1 if period == "year" else 5
    return now.replace(year=year, month=month, day=min(now.day, calendar.monthrange(year, month)[1]))


def probe(currency, period, now):
    start, end = int(beginning(now, period).timestamp()), int(now.timestamp())
    step = 3600 if period in ("week", "month") else 86400
    rows, calls = [], 0
    cursor = start // step * step
    while cursor <= end:
        if currency == "USD":
            url = "https://www.bitstamp.net/api/v2/ohlc/btcusd/?" + urllib.parse.urlencode({"step": step, "limit": min(1000, (end-cursor)//step+1), "start": cursor})
            data = get(url)["data"]["ohlc"]
            page = [(int(x["timestamp"]), float(x["close"])) for x in data]
        else:
            url = "https://data-api.binance.vision/api/v3/klines?" + urllib.parse.urlencode({"symbol": "BTC"+currency, "interval": "1h" if step == 3600 else "1d", "limit": 1000, "startTime": cursor*1000, "endTime": end*1000})
            page = [(int(x[0])//1000, float(x[4])) for x in get(url)]
        calls += 1
        if not page:
            break
        rows.extend(page)
        following = max(x[0] for x in page) + step
        if following <= cursor:
            raise ValueError("Paginação não avança")
        cursor = following
        time.sleep(0.25)
    rows = sorted(set(x for x in rows if start <= x[0] <= end))
    gaps = sum(b[0]-a[0] > step for a, b in zip(rows, rows[1:]))
    return {"currency": currency, "period": period, "requested_start": start, "requested_end": end, "step": step, "calls": calls, "count": len(rows), "first": rows[0] if rows else None, "last": rows[-1] if rows else None, "gaps": gaps, "nonpositive": sum(x[1] <= 0 for x in rows)}


if __name__ == "__main__":
    now = dt.datetime.now(dt.timezone.utc)
    report = {"checked_at": now.isoformat(), "results": [], "quotes": {}}
    for currency in ("BRL", "EUR", "USD"):
        try:
            url = "https://www.bitstamp.net/api/v2/ticker/btcusd/" if currency == "USD" else "https://data-api.binance.vision/api/v3/ticker/24hr?symbol=BTC" + currency
            data = get(url)
            report["quotes"][currency] = {"price": data.get("last", data.get("lastPrice")), "timestamp": data.get("timestamp", data.get("closeTime"))}
        except Exception as error:
            report["quotes"][currency] = {"error": str(error)}
        for period in ("week", "month", "year", "five"):
            try:
                result = probe(currency, period, now)
            except Exception as error:
                result = {"currency": currency, "period": period, "error": str(error)}
            report["results"].append(result)
            print(json.dumps(result), flush=True)
    with open("docs/provider-validation.json", "w") as file:
        json.dump(report, file, indent=2)
        file.write("\n")

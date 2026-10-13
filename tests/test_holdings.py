import datetime as dt
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
from io import BytesIO

spec = importlib.util.spec_from_file_location("holdings", Path(__file__).resolve().parents[1] / "plugin/holdings.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)


class AmountTests(unittest.TestCase):
    def test_exact_satoshis_and_decimal_calculation(self):
        self.assertEqual(h.parse_amount("0,00000001"), 1)
        self.assertEqual(h.parse_amount("1.23456789"), 123456789)
        self.assertEqual(h.parse_amount("0"), 0)
        self.assertEqual(h.total(1, "417759.01"), Decimal("0.0041775901"))
        self.assertEqual(h.parse_amount(h.amount_text(h.MAX_SATS)), h.MAX_SATS)

    def test_reject_bad_and_unsafe_values(self):
        for text in ("", "-1", "+1", "NaN", "inf", "1e-8", "1.000000001", "1,000.00", "1 000", "1.", "٠.١", "90071992.54740992"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                h.parse_amount(text)


class HistoryTests(unittest.TestCase):
    def test_calendar_month_leap_and_utc(self):
        now = dt.datetime(2024, 3, 31, 23, 45, tzinfo=dt.timezone.utc).timestamp()
        start, end, step = h.bounds("month", now)
        self.assertEqual(dt.datetime.fromtimestamp(start, dt.timezone.utc), dt.datetime(2024, 2, 29, 23, 45, tzinfo=dt.timezone.utc))
        start, _, _ = h.bounds("year", dt.datetime(2024, 2, 29, tzinfo=dt.timezone.utc).timestamp())
        self.assertEqual(dt.datetime.fromtimestamp(start, dt.timezone.utc).day, 28)
        self.assertEqual(h.bounds("week", now)[1] - h.bounds("week", now)[0], 7 * 86400)
        self.assertEqual(step, 3600)

    def test_order_duplicates_gaps_and_invalid_prices(self):
        self.assertEqual(h.normalize([[3, 5], [1, 2], [3, 6], [7, 4]], 0, 5), [[1, 2], [3, 6]])
        self.assertEqual(h.normalize([], 0, 5), [])
        self.assertEqual(h.normalize([[1, 2]], 0, 5), [[1, 2]])
        for price in (0, -1, float("nan"), float("inf"), True):
            with self.assertRaises(ValueError):
                h.normalize([[1, price]], 0, 5)

    def test_pagination_and_currency_never_convert(self):
        now = int(dt.datetime(2026, 10, 13, 17, tzinfo=dt.timezone.utc).timestamp())
        urls = []
        def get(url):
            from urllib.parse import urlparse, parse_qs
            urls.append(url)
            params = parse_qs(urlparse(url).query)
            cursor = int(params["startTime"][0]) // 1000
            end = int(params["endTime"][0]) // 1000
            return [[t * 1000, "1", "2", "1", "100", "1", (t + 86400) * 1000 - 1, "1", 1, "1", "1", "0"] for t in range(cursor, min(cursor + 1000 * 86400, end + 1), 86400)]
        result = h.history("BRL", "five", now, get)
        self.assertEqual(len(urls), 2)
        self.assertIn(len(result["points"]), (1826, 1827))
        self.assertEqual(result["gaps"], 0)
        self.assertTrue(all("symbol=BTCBRL" in url for url in urls))
        self.assertEqual(result["points"][-1][0], now)
        with self.assertRaises(ValueError):
            h.quote("EUR", now, lambda _: {"symbol": "BTCBRL", "lastPrice": "1", "closeTime": now * 1000})

    def test_bitstamp_uses_direct_usd_and_close_time(self):
        now = 1791912669
        start, _, step = h.bounds("week", now)
        calls = []
        def get(url):
            calls.append(url)
            return {"data": {"pair": "BTC/USD", "ohlc": [{"timestamp": str(now // step * step), "close": "80000"}]}}
        result = h.history("USD", "week", now, get)
        self.assertEqual(result["points"], [[now, 80000]])
        self.assertTrue(all("btcusd" in url and "end=" not in url for url in calls))


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1791912669
        self.urls = []
        self.error = None
        def get(url):
            self.urls.append(url)
            if self.error:
                raise self.error
            return {"symbol": "BTCBRL", "lastPrice": "417759.01", "closeTime": self.now * 1000}
        self.store = h.Store(self.temp.name + "/config", self.temp.name + "/cache", lambda: self.now, get)

    def tearDown(self):
        self.temp.cleanup()

    def test_zero_persistence_permissions_and_private_requests(self):
        self.assertIsNone(self.store.load())
        saved = self.store.save("0,00000001", "BRL")
        self.assertEqual(self.store.load(), saved)
        self.assertEqual(self.store.config.stat().st_mode & 0o777, 0o600)
        self.store.market("quote", "BRL")
        before = len(self.urls)
        self.store.save("0", "BRL")
        self.assertEqual(self.store.load()["satoshis"], 0)
        self.store.market("quote", "BRL")
        self.assertEqual(len(self.urls), before)
        self.assertTrue(all("amount" not in url and "satoshis" not in url for url in self.urls))
        for file in self.store.cache.glob("*.json"):
            self.assertNotIn("satoshis", file.read_text())

    def test_failure_keeps_valid_quote_and_backoff_survives_restart(self):
        good = self.store.market("quote", "BRL")
        self.now += 301
        self.error = h.ProviderError("Sem conexão.", "offline")
        stale = self.store.market("quote", "BRL")
        self.assertEqual(stale["status"], "stale")
        self.assertEqual(stale["failure"], "offline")
        self.assertEqual(stale["data"]["price"], good["data"]["price"])
        count = len(self.urls)
        self.store.market("quote", "BRL", force=True)
        self.assertEqual(len(self.urls), count)
        other = h.Store(self.temp.name + "/config", self.temp.name + "/cache", lambda: self.now, lambda _: self.fail("Backoff deve impedir consulta"))
        self.assertEqual(other.market("quote", "BRL")["status"], "stale")

    def test_429_respects_retry_after_and_no_zero_on_failure(self):
        self.error = h.ProviderError("Limite", retry_after=1800)
        reply = self.store.market("quote", "BRL")
        self.assertIsNone(reply["data"])
        self.assertEqual(reply["retry_at"], self.now + 1800)
        self.now += 901
        self.store.market("quote", "BRL", force=True)
        self.assertEqual(len(self.urls), 1)

    def test_bad_currency_response_preserves_cache(self):
        self.store.market("quote", "BRL")
        self.store.get = lambda _: {"symbol": "BTCEUR", "lastPrice": "1", "closeTime": self.now * 1000}
        reply = self.store.market("quote", "BRL", force=True)
        self.assertEqual(reply["status"], "stale")
        self.assertEqual(reply["data"]["price"], 417759.01)
        self.assertIsNone(self.store.market("quote", "EUR", cache_only=True)["data"])

    def test_corrupt_configuration_does_not_invent_balance(self):
        h.write_json(self.store.config, {"version": 1, "satoshis": -1, "currency": "BRL"})
        with self.assertRaises(ValueError):
            self.store.load()

    def test_load_preloads_expired_history_without_network(self):
        self.store.save("0", "BRL")
        for period in h.PERIODS:
            start, end, step = h.bounds(period, self.now)
            path, _ = self.store.cached("history", "BRL", period)
            h.write_json(path, {"kind": "history", "currency": "BRL", "period": period,
                               "fetched_at": self.now - 7200, "start": start, "end": end,
                               "step": step, "points": [[start, 100], [end, 200]], "gaps": 0})
        reply = self.store.handle({"command": "load"})
        self.assertEqual(set(reply["histories"]), set(h.PERIODS))
        self.assertEqual(reply["histories"]["five"]["points"][-1][1], 200)
        self.assertEqual(self.urls, [])
        path, _ = self.store.cached("history", "BRL", "month")
        data = h.read_json(path)
        data["currency"] = "EUR"
        h.write_json(path, data)
        self.assertNotIn("month", self.store.handle({"command": "load"})["histories"])


class HttpTests(unittest.TestCase):
    def test_invalid_timeout_and_size(self):
        class Response(BytesIO):
            pass
        with patch.object(h.urllib.request, "urlopen", return_value=Response(b"not-json")):
            with self.assertRaises(h.ProviderError): h.request_json("https://example.test")
        with patch.object(h.urllib.request, "urlopen", return_value=Response(b"x" * (h.MAX_BYTES + 1))):
            with self.assertRaises(h.ProviderError): h.request_json("https://example.test")
        with patch.object(h.urllib.request, "urlopen", side_effect=TimeoutError()):
            with self.assertRaises(h.ProviderError) as caught: h.request_json("https://example.test")
            self.assertEqual(caught.exception.state, "offline")

    def test_retry_after_date_and_header(self):
        self.assertEqual(h.retry_seconds("120", 0), 120)
        self.assertEqual(h.retry_seconds("Thu, 01 Jan 1970 00:02:00 GMT", 0), 120)
        error = urllib.error.HTTPError("https://example.test", 429, "limit", {"Retry-After": "1800"}, None)
        with patch.object(h.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(h.ProviderError) as caught: h.request_json("https://example.test")
            self.assertEqual(caught.exception.retry_after, 1800)


if __name__ == "__main__":
    unittest.main()

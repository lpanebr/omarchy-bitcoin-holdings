"""Modelo local e protocolo JSON por stdin/stdout para o widget Quickshell."""
import calendar
import contextlib
import datetime as dt
from decimal import Decimal
import email.utils
import fcntl
import json
import math
import os
from pathlib import Path
import re
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PLUGIN_ID = "io.github.lpanebr.bitcoin-holdings"
MAX_SATS = 9007199254740991
MAX_BYTES = 2 * 1024 * 1024
CURRENCIES = ("BRL", "USD", "EUR")
PERIODS = ("week", "month", "year", "five")


def parse_amount(text):
    value = str(text).strip()
    if not re.fullmatch(r"[0-9]+(?:[.,][0-9]{1,8})?", value) or len(value) > 30:
        raise ValueError("Informe BTC com até oito casas decimais, sem sinal ou separador de milhar.")
    sats = int(Decimal(value.replace(",", ".")) * 100_000_000)
    if sats > MAX_SATS:
        raise ValueError("Quantidade excede o limite inteiro seguro.")
    return sats


def amount_text(sats):
    return format(Decimal(sats) / 100_000_000, "f")


def total(sats, price):
    return Decimal(sats) * Decimal(str(price)) / 100_000_000


def bounds(period, now):
    current = dt.datetime.fromtimestamp(now, dt.timezone.utc)
    if period == "week":
        previous = current - dt.timedelta(days=7)
    else:
        year, month = current.year, current.month
        if period == "month":
            month -= 1
            if month == 0:
                year, month = year - 1, 12
        elif period in ("year", "five"):
            year -= 1 if period == "year" else 5
        else:
            raise ValueError("Período inválido.")
        previous = current.replace(year=year, month=month, day=min(current.day, calendar.monthrange(year, month)[1]))
    return int(previous.timestamp()), int(now), 3600 if period in ("week", "month") else 86400


def finite_price(value):
    if isinstance(value, bool):
        raise ValueError("Preço inválido.")
    price = float(value)
    if not math.isfinite(price) or price <= 0:
        raise ValueError("Preço inválido.")
    return price


def timestamp(value):
    if isinstance(value, bool):
        raise ValueError("Data inválida.")
    parsed = int(value)
    if float(value) != parsed or parsed < 0:
        raise ValueError("Data inválida.")
    return parsed


def normalize(points, start, end):
    if not isinstance(points, list) or len(points) > 2000:
        raise ValueError("Histórico inválido ou grande demais.")
    ordered = {}
    for row in points:
        if not isinstance(row, (list, tuple)) or len(row) != 2:
            raise ValueError("Ponto inválido.")
        moment, price = timestamp(row[0]), finite_price(row[1])
        if start <= moment <= end:
            ordered[moment] = price  # Última ocorrência vence; nunca inventar data.
    return [[moment, price] for moment, price in sorted(ordered.items())]


def source(currency):
    return "Bitstamp · BTC/USD" if currency == "USD" else "Binance · BTC/" + currency


class ProviderError(Exception):
    def __init__(self, message, state="unavailable", retry_after=None):
        super().__init__(message)
        self.state, self.retry_after = state, retry_after


def retry_seconds(value, now):
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        try:
            return max(0, email.utils.parsedate_to_datetime(value).timestamp() - now)
        except (TypeError, ValueError, OverflowError):
            return None


def request_json(url):
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "Omarchy-Bitcoin-Holdings/0.1", "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=12) as response:
            raw = response.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ProviderError("Resposta do provedor excede o limite local.")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        retry = retry_seconds(error.headers.get("Retry-After"), time.time())
        raise ProviderError("Provedor limitou consultas (HTTP %s)." % error.code if error.code in (429, 418) else "Provedor indisponível (HTTP %s)." % error.code, "unavailable", retry) from error
    except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionError) as error:
        raise ProviderError("Sem conexão ou tempo de consulta esgotado.", "offline") from error
    except (ValueError, UnicodeError) as error:
        raise ProviderError("Resposta inválida do provedor.") from error


def quote(currency, now, get=request_json):
    if currency == "USD":
        data = get("https://www.bitstamp.net/api/v2/ticker/btcusd/")
        price, moment = finite_price(data["last"]), timestamp(data["timestamp"])
    else:
        data = get("https://data-api.binance.vision/api/v3/ticker/24hr?" + urllib.parse.urlencode({"symbol": "BTC" + currency}))
        if data["symbol"] != "BTC" + currency:
            raise ValueError("Moeda incorreta na resposta.")
        price, moment = finite_price(data["lastPrice"]), timestamp(data["closeTime"]) // 1000
    if moment > now + 60:
        raise ValueError("Cotação com data futura.")
    return {"price": price, "timestamp": moment}


def history(currency, period, now, get=request_json):
    start, end, step = bounds(period, now)
    cursor, points = start // step * step, []
    for _ in range(3):
        if cursor > end:
            break
        if currency == "USD":
            size = min(1000, (end - cursor) // step + 1)
            url = "https://www.bitstamp.net/api/v2/ohlc/btcusd/?" + urllib.parse.urlencode({"step": step, "limit": size, "start": cursor})
            data = get(url)["data"]
            if data["pair"] != "BTC/USD":
                raise ValueError("Moeda incorreta na resposta.")
            page = data["ohlc"]
            if not isinstance(page, list) or len(page) > 1000:
                raise ValueError("Página inválida.")
            raw = [(timestamp(row["timestamp"]), finite_price(row["close"])) for row in page]
            chunk = [[min(t + step, end), p] for t, p in raw if t <= end]
        else:
            url = "https://data-api.binance.vision/api/v3/klines?" + urllib.parse.urlencode({"symbol": "BTC" + currency, "interval": "1h" if step == 3600 else "1d", "limit": 1000, "startTime": cursor * 1000, "endTime": end * 1000})
            page = get(url)
            if not isinstance(page, list) or len(page) > 1000:
                raise ValueError("Página inválida.")
            raw, chunk = [], []
            for row in page:
                if not isinstance(row, list) or len(row) != 12:
                    raise ValueError("Candle inválido.")
                t, closing, price = timestamp(row[0]) // 1000, timestamp(row[6]) // 1000, finite_price(row[4])
                if closing < t or closing - t > step:
                    raise ValueError("Intervalo de candle inválido.")
                raw.append((t, price))
                chunk.append([min(closing + 1, end), price])
        if not raw:
            break
        following = max(t for t, _ in raw) + step
        if following <= cursor:
            raise ValueError("Paginação sem avanço.")
        points.extend(chunk)
        cursor = following
    else:
        if cursor <= end:
            raise ValueError("Histórico excede limite de páginas.")
    points = normalize(points, start, end)
    if not points:
        raise ValueError("Provedor retornou série vazia.")
    return {"points": points, "start": start, "end": end, "step": step,
            "gaps": sum(b[0] - a[0] > step * 1.5 for a, b in zip(points, points[1:]))}


def read_json(path):
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
        return json.loads(raw) if len(raw) <= MAX_BYTES else None
    except (OSError, ValueError, UnicodeError):
        return None


def write_json(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".holdings-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(data, stream, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Store:
    def __init__(self, config_home=None, cache_home=None, clock=time.time, get=request_json):
        self.config = Path(config_home or os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / PLUGIN_ID / "config.json"
        self.cache = Path(cache_home or os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / PLUGIN_ID
        self.clock, self.get = clock, get

    @contextlib.contextmanager
    def locked(self):
        self.cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor = os.open(self.cache / "requests.lock", os.O_CREAT | os.O_RDWR, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            yield

    def load(self):
        saved = read_json(self.config)
        if saved is None:
            if self.config.exists():
                raise ValueError("Configuração local ilegível; abra Configurar BTC para corrigir.")
            return None
        sats = saved.get("satoshis") if isinstance(saved, dict) else None
        if type(sats) is not int or not 0 <= sats <= MAX_SATS or saved.get("currency") not in CURRENCIES or saved.get("version") != 1:
            raise ValueError("Configuração local inválida; abra Configurar BTC para corrigir.")
        return {"satoshis": sats, "amount": amount_text(sats), "currency": saved["currency"]}

    def save(self, text, currency):
        if currency not in CURRENCIES:
            raise ValueError("Moeda não suportada.")
        sats = parse_amount(text)
        write_json(self.config, {"version": 1, "satoshis": sats, "currency": currency})
        return self.load()

    def cached(self, kind, currency, period):
        key = "%s-%s-%s.json" % (kind, currency, period if kind == "history" else "current")
        path = self.cache / key
        data = read_json(path)
        try:
            if data["currency"] != currency or data["kind"] != kind or data["period"] != period:
                return path, None
            timestamp(data["fetched_at"])
            if kind == "quote":
                finite_price(data["price"])
                timestamp(data["timestamp"])
            else:
                if data["step"] not in (3600, 86400) or not data["points"]:
                    return path, None
                data["points"] = normalize(data["points"], timestamp(data["start"]), timestamp(data["end"]))
            return path, data
        except (TypeError, KeyError, ValueError, OverflowError):
            return path, None

    def market(self, kind, currency, period="month", force=False, cache_only=False):
        if currency not in CURRENCIES or period not in PERIODS or kind not in ("quote", "history"):
            raise ValueError("Consulta inválida.")
        if kind == "quote":
            period = "month"  # Cotação atual independe do período selecionado.
        with self.locked():
            path, cached = self.cached(kind, currency, period)
            now = int(self.clock())
            ttl = 300 if kind == "quote" or period in ("week", "month") else 3600
            state_path = self.cache / ("backoff-" + ("bitstamp" if currency == "USD" else "binance") + ".json")
            backoff = read_json(state_path) or {}
            if cache_only or (cached and not force and 0 <= now - cached["fetched_at"] < ttl):
                return self.result(cached, kind, currency, period, now, ttl)
            if now < backoff.get("until", 0):
                return self.result(cached, kind, currency, period, now, ttl, backoff.get("message", "Aguardando provedor."), backoff.get("state", "unavailable"), backoff["until"])
            try:
                data = quote(currency, now, self.get) if kind == "quote" else history(currency, period, now, self.get)
                data.update({"currency": currency, "kind": kind, "period": period, "fetched_at": now, "source": source(currency)})
                write_json(path, data)
                write_json(state_path, {})
                return self.result(data, kind, currency, period, now, ttl)
            except (ProviderError, ValueError, KeyError, TypeError, OverflowError) as error:
                state = error.state if isinstance(error, ProviderError) else "unavailable"
                failures = min(6, int(backoff.get("failures", 0)) + 1)
                delay = min(900, 30 * 2 ** (failures - 1))
                if isinstance(error, ProviderError) and error.retry_after is not None:
                    delay = max(delay, error.retry_after)
                message = str(error) if isinstance(error, ProviderError) else "Resposta inválida do provedor."
                until = now + delay
                write_json(state_path, {"failures": failures, "until": until, "message": message, "state": state})
                return self.result(cached, kind, currency, period, now, ttl, message, state, until)

    @staticmethod
    def result(data, kind, currency, period, now, ttl, error="", failure="unavailable", retry_at=0):
        old = bool(data and (now - data["fetched_at"] >= ttl or (kind == "quote" and now - data["timestamp"] > 600)))
        status = "stale" if data and (old or error) else ("ready" if data else failure)
        return {"kind": kind, "currency": currency, "period": period, "data": data,
                "status": status, "failure": failure if error else "", "error": error, "retry_at": retry_at}

    def handle(self, message):
        command = message.get("command")
        if command == "load":
            config = self.load()
            cached = self.market("quote", config["currency"], cache_only=True) if config else None
            histories = {}
            if config:
                for period in PERIODS:
                    _, data = self.cached("history", config["currency"], period)
                    if data:
                        histories[period] = data
            return {"kind": "config", "config": config, "quote": cached, "histories": histories}
        if command == "save":
            return {"kind": "config", "config": self.save(message.get("amount", ""), message.get("currency"))}
        if command in ("quote", "history"):
            return self.market(command, message.get("currency"), message.get("period", "month"), message.get("force") is True, message.get("cache_only") is True)
        raise ValueError("Comando inválido.")


def main():
    store = Store()
    while True:
        line = sys.stdin.buffer.readline(16385)
        if not line:
            break
        if len(line) > 16384:
            break
        message = {}
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError("Mensagem inválida.")
            response = store.handle(message)
            response["ok"] = True
        except (ValueError, OSError, TypeError) as error:
            response = {"ok": False, "error": str(error) if isinstance(error, ValueError) else "Não foi possível acessar os arquivos locais."}
        response["id"] = message.get("id") if isinstance(message, dict) else None
        print(json.dumps(response, ensure_ascii=False, allow_nan=False, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()

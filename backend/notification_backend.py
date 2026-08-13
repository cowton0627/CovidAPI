from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import subprocess
import tempfile
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable, Iterable

CDC_URL = "https://www.cdc.gov.tw/TravelEpidemic/ExportJSON"
DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9._~-]{16,128}$")
PUSH_TOKEN_RE = re.compile(r"^[0-9A-Fa-f]{32,512}$")


def now() -> float:
    return time.time()


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = WAL")
    db.execute("PRAGMA busy_timeout = 15000")
    return db


def migrate(db: sqlite3.Connection) -> None:
    db.executescript("""
    CREATE TABLE IF NOT EXISTS epidemic_items (
      identifier TEXT PRIMARY KEY,
      location TEXT NOT NULL,
      headline TEXT NOT NULL,
      published_at REAL NOT NULL,
      content_hash TEXT NOT NULL,
      first_seen_at REAL NOT NULL,
      last_seen_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS device_tokens (
      device_id TEXT PRIMARY KEY,
      token TEXT NOT NULL UNIQUE,
      platform TEXT NOT NULL CHECK(platform = 'ios'),
      favorite_locations TEXT NOT NULL,
      notifications_enabled INTEGER NOT NULL,
      updated_at REAL NOT NULL,
      last_success_at REAL
    );
    CREATE TABLE IF NOT EXISTS notification_deliveries (
      item_identifier TEXT NOT NULL REFERENCES epidemic_items(identifier),
      device_id TEXT NOT NULL REFERENCES device_tokens(device_id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'pending',
      retry_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at REAL NOT NULL,
      apns_id TEXT,
      last_error TEXT,
      PRIMARY KEY(item_identifier, device_id)
    );
    CREATE TABLE IF NOT EXISTS service_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    """)
    db.commit()


def validate_locations(value: object) -> list[str]:
    if not isinstance(value, list) or len(value) > 100:
        raise ValueError("favoriteLocations must be an array with at most 100 items")
    locations: list[str] = []
    for item in value:
        if not isinstance(item, str) or not (1 <= len(item.strip()) <= 120):
            raise ValueError("favoriteLocations contains an invalid value")
        locations.append(item.strip())
    return sorted(set(locations))


def validate_registration(body: object) -> tuple[str, bool, list[str]]:
    if not isinstance(body, dict) or set(body) != {
        "platform", "pushToken", "notificationsEnabled", "favoriteLocations"
    }:
        raise ValueError("registration fields do not match the API contract")
    token = body["pushToken"]
    enabled = body["notificationsEnabled"]
    if body["platform"] != "ios" or not isinstance(token, str) or not PUSH_TOKEN_RE.fullmatch(token):
        raise ValueError("platform or pushToken is invalid")
    if not isinstance(enabled, bool):
        raise ValueError("notificationsEnabled must be a boolean")
    return token.lower(), enabled, validate_locations(body["favoriteLocations"])


def validate_preferences(body: object) -> tuple[bool, list[str]]:
    if not isinstance(body, dict) or set(body) != {"notificationsEnabled", "favoriteLocations"}:
        raise ValueError("preference fields do not match the API contract")
    enabled = body["notificationsEnabled"]
    if not isinstance(enabled, bool):
        raise ValueError("notificationsEnabled must be a boolean")
    return enabled, validate_locations(body["favoriteLocations"])


def upsert_device(db: sqlite3.Connection, device_id: str, body: object) -> None:
    token, enabled, locations = validate_registration(body)
    db.execute("DELETE FROM device_tokens WHERE token = ? AND device_id <> ?", (token, device_id))
    db.execute("""
      INSERT INTO device_tokens
        (device_id, token, platform, favorite_locations, notifications_enabled, updated_at)
      VALUES (?, ?, 'ios', ?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET token=excluded.token,
        favorite_locations=excluded.favorite_locations,
        notifications_enabled=excluded.notifications_enabled, updated_at=excluded.updated_at
    """, (device_id, token, json.dumps(locations, ensure_ascii=False), enabled, now()))
    db.commit()


def update_preferences(db: sqlite3.Connection, device_id: str, body: object) -> bool:
    enabled, locations = validate_preferences(body)
    cursor = db.execute("""
      UPDATE device_tokens SET notifications_enabled=?, favorite_locations=?, updated_at=?
      WHERE device_id=?
    """, (enabled, json.dumps(locations, ensure_ascii=False), now(), device_id))
    db.commit()
    return cursor.rowcount > 0


def parse_date(value: object) -> float:
    if not isinstance(value, str):
        raise ValueError("effective must be an ISO-8601 string")
    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


@dataclass(frozen=True)
class Epidemic:
    identifier: str
    location: str
    headline: str
    published_at: float
    content_hash: str


def parse_epidemics(payload: object) -> list[Epidemic]:
    if not isinstance(payload, list) or not payload:
        raise ValueError("CDC response must be a non-empty array")
    result = []
    for raw in payload:
        if not isinstance(raw, dict):
            raise ValueError("CDC item must be an object")
        headline, description = raw.get("headline"), raw.get("description")
        if not isinstance(headline, str) or not headline.strip() or not isinstance(description, str):
            raise ValueError("CDC item is missing headline or description")
        published = parse_date(raw.get("effective"))
        area = raw.get("areaDesc")
        location = area.strip() if isinstance(area, str) and area.strip() else headline.split("-", 1)[0].strip()
        identifier = f"{headline}|{published:.1f}"
        digest = hashlib.sha256(json.dumps(raw, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        result.append(Epidemic(identifier, location, headline, published, digest))
    return result


def fetch_cdc(url: str = CDC_URL) -> list[Epidemic]:
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "CovidAPI-notifier/1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status // 100 != 2:
            raise RuntimeError(f"CDC returned HTTP {response.status}")
        return parse_epidemics(json.load(response))


def sync_epidemics(db: sqlite3.Connection, items: Iterable[Epidemic], enqueue: bool = True) -> tuple[int, int]:
    observed = now()
    new_count = changed_count = 0
    with db:
        for item in items:
            previous = db.execute(
                "SELECT content_hash FROM epidemic_items WHERE identifier=?", (item.identifier,)
            ).fetchone()
            if previous is None:
                new_count += 1
                db.execute("""
                  INSERT INTO epidemic_items VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (item.identifier, item.location, item.headline, item.published_at,
                      item.content_hash, observed, observed))
            else:
                changed = previous["content_hash"] != item.content_hash
                changed_count += int(changed)
                db.execute("""
                  UPDATE epidemic_items SET location=?, headline=?, published_at=?,
                    content_hash=?, last_seen_at=? WHERE identifier=?
                """, (item.location, item.headline, item.published_at, item.content_hash,
                      observed, item.identifier))
            if enqueue and previous is None:
                devices = db.execute(
                    "SELECT device_id, favorite_locations FROM device_tokens WHERE notifications_enabled=1"
                )
                for device in devices:
                    if item.location in json.loads(device["favorite_locations"]):
                        db.execute("""
                          INSERT OR IGNORE INTO notification_deliveries
                            (item_identifier, device_id, next_attempt_at) VALUES (?, ?, ?)
                        """, (item.identifier, device["device_id"], observed))
        db.execute("INSERT OR REPLACE INTO service_state VALUES ('last_cdc_success', ?)", (str(observed),))
    return new_count, changed_count


def notification_payload(identifier: str, headline: str) -> dict:
    return {"aps": {"alert": {"title": "新的旅遊疫情資訊", "body": headline[:160]},
                    "sound": "default"}, "epidemicIdentifier": identifier}


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_jose(signature: bytes, part_size: int = 32) -> bytes:
    """Convert OpenSSL's ASN.1 ECDSA signature to JWT's fixed-width R || S."""
    if len(signature) < 8 or signature[0] != 0x30:
        raise ValueError("invalid ECDSA signature")
    offset = 2
    if signature[1] & 0x80:
        length_bytes = signature[1] & 0x7F
        offset = 2 + length_bytes
    parts = []
    for _ in range(2):
        if offset + 2 > len(signature) or signature[offset] != 0x02:
            raise ValueError("invalid ECDSA integer")
        length = signature[offset + 1]
        offset += 2
        value = signature[offset:offset + length].lstrip(b"\x00")
        if len(value) > part_size:
            raise ValueError("ECDSA integer is too large")
        parts.append(value.rjust(part_size, b"\x00"))
        offset += length
    return b"".join(parts)


def apns_jwt(key_id: str, team_id: str, private_key: str) -> str:
    header = base64url(json.dumps({"alg": "ES256", "kid": key_id}, separators=(",", ":")).encode())
    claims = base64url(json.dumps({"iss": team_id, "iat": int(now())}, separators=(",", ":")).encode())
    unsigned = f"{header}.{claims}"
    with tempfile.NamedTemporaryFile("w") as key_file:
        os.chmod(key_file.name, 0o600)
        key_file.write(private_key)
        key_file.flush()
        der_signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_file.name], input=unsigned.encode(),
            capture_output=True, check=True
        ).stdout
    return f"{unsigned}.{base64url(der_to_jose(der_signature))}"


def send_apns(token: str, payload: dict, jwt: str, topic: str, production: bool) -> tuple[int, str, str]:
    host = "api.push.apple.com" if production else "api.sandbox.push.apple.com"
    command = ["curl", "--silent", "--show-error", "--http2", "--max-time", "30",
               "--request", "POST", "--header", f"authorization: bearer {jwt}",
               "--header", f"apns-topic: {topic}", "--header", "apns-push-type: alert",
               "--header", "content-type: application/json", "--data-binary", json.dumps(payload),
               "--write-out", "\n%{http_code}\n%header{apns-id}", f"https://{host}/3/device/{token}"]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    body, status, apns_id = result.stdout.rsplit("\n", 2)
    return int(status), apns_id.strip(), body


def dispatch_pending(db: sqlite3.Connection, sender: Callable[[str, dict], tuple[int, str, str]], limit: int = 100) -> dict:
    rows = db.execute("""
      SELECT d.item_identifier, d.device_id, d.retry_count, t.token, e.headline
      FROM notification_deliveries d JOIN device_tokens t USING(device_id)
      JOIN epidemic_items e ON e.identifier=d.item_identifier
      WHERE d.status IN ('pending','retry') AND d.next_attempt_at <= ?
      ORDER BY d.next_attempt_at LIMIT ?
    """, (now(), limit)).fetchall()
    stats = {"sent": 0, "retried": 0, "invalid": 0}
    for row in rows:
        status, apns_id, error = sender(row["token"], notification_payload(row["item_identifier"], row["headline"]))
        if status == 200:
            db.execute("UPDATE notification_deliveries SET status='sent', apns_id=?, last_error=NULL WHERE item_identifier=? AND device_id=?",
                       (apns_id, row["item_identifier"], row["device_id"]))
            db.execute("UPDATE device_tokens SET last_success_at=? WHERE device_id=?", (now(), row["device_id"]))
            stats["sent"] += 1
        elif status in (400, 410) and ("BadDeviceToken" in error or "Unregistered" in error):
            db.execute("DELETE FROM device_tokens WHERE device_id=?", (row["device_id"],))
            stats["invalid"] += 1
        else:
            retries = row["retry_count"] + 1
            delay = min(3600, 30 * (2 ** min(retries - 1, 7)))
            db.execute("""
              UPDATE notification_deliveries SET status='retry', retry_count=?, next_attempt_at=?,
                last_error=? WHERE item_identifier=? AND device_id=?
            """, (retries, now() + delay, error[:500], row["item_identifier"], row["device_id"]))
            stats["retried"] += 1
        db.commit()
    return stats


def make_apns_sender() -> Callable[[str, dict], tuple[int, str, str]]:
    required = ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC"]
    missing = [name for name in required if not os.getenv(name)]
    private_key = os.getenv("APNS_PRIVATE_KEY")
    private_key_file = os.getenv("APNS_PRIVATE_KEY_FILE")
    if not private_key and private_key_file:
        private_key = Path(private_key_file).read_text()
    if not private_key:
        missing.append("APNS_PRIVATE_KEY or APNS_PRIVATE_KEY_FILE")
    if missing:
        raise ValueError("missing APNs settings: " + ", ".join(missing))
    jwt = apns_jwt(os.environ["APNS_KEY_ID"], os.environ["APNS_TEAM_ID"], private_key)
    return lambda token, payload: send_apns(
        token, payload, jwt, os.environ["APNS_TOPIC"],
        os.getenv("APNS_ENVIRONMENT", "sandbox") == "production"
    )


def run_worker(database: str, interval: int, dispatch_enabled: bool) -> None:
    """Continuously synchronize CDC and drain deliveries for a single staging worker."""
    while True:
        started = now()
        try:
            items = fetch_cdc(os.getenv("CDC_URL", CDC_URL))
            with connect(database) as db:
                migrate(db)
                new, changed = sync_epidemics(db, items, enqueue=dispatch_enabled)
                result: dict[str, object] = {"new": new, "changed": changed}
                if dispatch_enabled:
                    result["dispatch"] = dispatch_pending(db, make_apns_sender())
            print(json.dumps({"event": "worker_cycle", **result}), flush=True)
        except Exception as error:
            print(json.dumps({"event": "worker_error", "type": type(error).__name__,
                              "message": str(error)}), flush=True)
        time.sleep(max(1, interval - int(now() - started)))


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "CovidAPINotifier/1"

    def send_json(self, status: int, body: object | None = None) -> None:
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def error_json(self, status: int, code: str, message: str) -> None:
        self.send_json(status, {"error": {"code": code, "message": message}})

    def authorized(self) -> bool:
        supplied = self.headers.get("Authorization", "").removeprefix("Bearer ")
        expected = self.server.access_token  # type: ignore[attr-defined]
        return bool(expected) and hmac.compare_digest(supplied, expected)

    def body(self) -> object:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 32_768:
            raise ValueError("request body size is invalid")
        return json.loads(self.rfile.read(length))

    def route(self) -> tuple[str | None, bool]:
        match = re.fullmatch(r"/v1/devices/([^/]+)(/preferences)?", self.path)
        return (match.group(1), bool(match.group(2))) if match else (None, False)

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self.send_json(200, {"status": "ok"})
        else:
            self.error_json(404, "not_found", "route not found")

    def mutate(self) -> None:
        if not self.authorized():
            self.error_json(401, "unauthorized", "missing or invalid access token")
            return
        device_id, preferences = self.route()
        if not device_id:
            self.error_json(404, "not_found", "route not found")
            return
        if not DEVICE_ID_RE.fullmatch(device_id):
            self.error_json(400, "invalid_request", "deviceId is invalid")
            return
        try:
            with connect(self.server.database_path) as db:  # type: ignore[attr-defined]
                if self.command == "PUT" and not preferences:
                    upsert_device(db, device_id, self.body())
                elif self.command == "PATCH" and preferences:
                    if not update_preferences(db, device_id, self.body()):
                        self.error_json(404, "not_found", "device not found")
                        return
                elif self.command == "DELETE" and not preferences:
                    db.execute("DELETE FROM device_tokens WHERE device_id=?", (device_id,))
                    db.commit()
                else:
                    self.error_json(405, "method_not_allowed", "method not allowed")
                    return
            self.send_json(204)
        except (ValueError, json.JSONDecodeError) as error:
            self.error_json(400, "invalid_request", str(error))

    do_PUT = mutate
    do_PATCH = mutate
    do_DELETE = mutate

    def log_message(self, fmt: str, *args: object) -> None:
        print(json.dumps({"time": datetime.now(timezone.utc).isoformat(), "message": fmt % args}))


def serve(database: str, token: str, host: str, port: int) -> None:
    with connect(database) as db:
        migrate(db)
    server = ThreadingHTTPServer((host, port), ApiHandler)
    server.database_path, server.access_token = database, token  # type: ignore[attr-defined]
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description="CovidAPI notification backend")
    parser.add_argument("--database", default=os.getenv("DATABASE_PATH", "notification-backend.sqlite3"))
    sub = parser.add_subparsers(dest="command", required=True)
    api = sub.add_parser("serve")
    api.add_argument("--host", default="127.0.0.1")
    api.add_argument("--port", type=int, default=int(os.getenv("PORT", "8080")))
    sync = sub.add_parser("sync")
    sync.add_argument("--dry-run", action="store_true")
    dispatch = sub.add_parser("dispatch")
    dispatch.add_argument("--limit", type=int, default=100)
    worker = sub.add_parser("worker")
    worker.add_argument("--interval", type=int, default=int(os.getenv("SYNC_INTERVAL_SECONDS", "900")))
    args = parser.parse_args()
    if args.command == "serve":
        token = os.environ.get("BACKEND_ACCESS_TOKEN", "")
        if not token:
            parser.error("BACKEND_ACCESS_TOKEN is required")
        serve(args.database, token, args.host, args.port)
        return
    if args.command == "worker":
        dispatch_enabled = os.getenv("PUSH_DISPATCH_ENABLED", "false").lower() == "true"
        run_worker(args.database, args.interval, dispatch_enabled)
        return
    with connect(args.database) as db:
        migrate(db)
        if args.command == "sync":
            new, changed = sync_epidemics(db, fetch_cdc(os.getenv("CDC_URL", CDC_URL)), not args.dry_run)
            print(json.dumps({"new": new, "changed": changed, "dryRun": args.dry_run}))
        elif args.command == "dispatch":
            try:
                sender = make_apns_sender()
            except ValueError as error:
                parser.error(str(error))
            print(json.dumps(dispatch_pending(db, sender, args.limit)))


if __name__ == "__main__":
    main()

import base64
import json
import subprocess
import sqlite3
import tempfile
import unittest

from backend.notification_backend import (
    Epidemic, apns_jwt, connect, der_to_jose, dispatch_pending, migrate, notification_payload,
    parse_epidemics, sync_epidemics, update_preferences, upsert_device,
)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.NamedTemporaryFile()
        self.db = connect(self.temp.name)
        migrate(self.db)

    def tearDown(self):
        self.db.close()
        self.temp.close()

    def registration(self, locations=None):
        return {"platform": "ios", "pushToken": "ab" * 32,
                "notificationsEnabled": True, "favoriteLocations": locations or ["日本"]}

    def test_device_upsert_and_preferences_are_idempotent(self):
        upsert_device(self.db, "device-identifier-1", self.registration())
        upsert_device(self.db, "device-identifier-1", self.registration())
        self.assertTrue(update_preferences(self.db, "device-identifier-1",
                                           {"notificationsEnabled": False, "favoriteLocations": ["美國"]}))
        row = self.db.execute("SELECT * FROM device_tokens").fetchone()
        self.assertEqual(json.loads(row["favorite_locations"]), ["美國"])
        self.assertEqual(row["notifications_enabled"], 0)

    def test_cdc_parser_matches_ios_identifier_and_area(self):
        item = parse_epidemics([{"headline": "加拿⼤-狂⽝病", "effective": "2023-11-14T22:13:20Z",
                                 "description": "test", "areaDesc": "加拿大"}])[0]
        self.assertEqual(item.identifier, "加拿⼤-狂⽝病|1700000000.0")
        self.assertEqual(item.location, "加拿大")

    def test_sync_only_enqueues_new_matching_items(self):
        upsert_device(self.db, "device-identifier-1", self.registration())
        item = Epidemic("日本-腸病毒|1700000000.0", "日本", "日本-腸病毒", 1700000000, "hash")
        self.assertEqual(sync_epidemics(self.db, [item]), (1, 0))
        self.assertEqual(sync_epidemics(self.db, [item]), (0, 0))
        count = self.db.execute("SELECT count(*) FROM notification_deliveries").fetchone()[0]
        self.assertEqual(count, 1)

    def test_dispatch_success_and_retry(self):
        upsert_device(self.db, "device-identifier-1", self.registration())
        item = Epidemic("日本-腸病毒|1700000000.0", "日本", "日本-腸病毒", 1700000000, "hash")
        sync_epidemics(self.db, [item])
        stats = dispatch_pending(self.db, lambda token, payload: (503, "", "ServiceUnavailable"))
        self.assertEqual(stats["retried"], 1)
        self.db.execute("UPDATE notification_deliveries SET next_attempt_at=0")
        stats = dispatch_pending(self.db, lambda token, payload: (200, "request-id", ""))
        self.assertEqual(stats["sent"], 1)

    def test_payload_matches_contract(self):
        payload = notification_payload("日本-腸病毒|1700000000.0", "日本-腸病毒")
        self.assertEqual(payload["aps"]["sound"], "default")
        self.assertEqual(payload["epidemicIdentifier"], "日本-腸病毒|1700000000.0")

    def test_der_signature_is_converted_to_fixed_width_jose(self):
        der = bytes.fromhex("3006020101020102")
        jose = der_to_jose(der)
        self.assertEqual(len(jose), 64)
        self.assertEqual(jose[31], 1)
        self.assertEqual(jose[63], 2)

    def test_apns_jwt_has_raw_es256_signature(self):
        with tempfile.NamedTemporaryFile() as key:
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey",
                            "-noout", "-out", key.name], check=True, capture_output=True)
            key.seek(0)
            token = apns_jwt("KEY123", "TEAM123", key.read().decode())
        signature = token.split(".")[2]
        signature += "=" * (-len(signature) % 4)
        self.assertEqual(len(base64.urlsafe_b64decode(signature)), 64)


if __name__ == "__main__":
    unittest.main()

import os
import sys
import json
import base64
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

TEST_DB_PATH = Path(__file__).resolve().parent / "test_vetify.db"
if TEST_DB_PATH.exists():
    try:
        os.remove(TEST_DB_PATH)
    except Exception:
        pass

os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH.as_posix()}"

from starlette.testclient import TestClient
from server.main import app, ADMIN_KEY
from server.crypto_service import verify_data, get_or_create_keypair, canonical_json
from server.database import Base, engine, SessionLocal
from server.dataset_service import compute_sha256, seed_v14_if_needed

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


class TestVetifyServerIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        db = SessionLocal()
        try:
            seed_v14_if_needed(db)
        finally:
            db.close()
        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls):
        if TEST_DB_PATH.exists():
            try:
                os.remove(TEST_DB_PATH)
            except Exception:
                pass

    def test_01_health_and_seed(self):
        """GET /health should report healthy and seed v14."""
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "healthy")
        self.assertEqual(data["database"], "connected")
        self.assertEqual(data["latest_version"], "v14")
        self.assertIn("public_key_hex", data)

    def test_02_manifest_etag_and_signature(self):
        """GET /v1/manifest should return signed manifest and support ETag 304."""
        response = self.client.get("/v1/manifest?schema=2&current=v14")
        self.assertEqual(response.status_code, 200)
        manifest = response.json()
        self.assertEqual(manifest["schema_version"], 2)
        self.assertEqual(manifest["latest_version"], "v14")
        self.assertFalse(manifest["delta_available"])
        self.assertIn("payload_signature", manifest)
        self.assertIn("payload_sha256", manifest)

        etag = response.headers.get("ETag")
        self.assertIsNotNone(etag)

        # 304 Not Modified
        cached_response = self.client.get(
            "/v1/manifest?schema=2&current=v14",
            headers={"If-None-Match": etag},
        )
        self.assertEqual(cached_response.status_code, 304)

        # Verify signature
        manifest_sig = response.headers.get("X-Manifest-Signature")
        self.assertIsNotNone(manifest_sig)
        canonical_manifest = canonical_json(manifest)
        self.assertTrue(verify_data(canonical_manifest, manifest_sig))

    def test_03_publishing_test_cases(self):
        """
        Tests the 4 publishing cases from the brief:
        - update_v15.json (Valid -> accepted)
        - update_v16.json (v13 < v14 -> rejected with 409 or 422)
        - update_v17.json (schema_version 3 -> rejected with 422)
        - update_v18.json (truncated JSON -> rejected with 422)
        """
        # Case 1: update_v18.json (truncated JSON)
        with open(DATA_DIR / "update_v18.json", "r", encoding="utf-8") as f:
            raw_v18 = f.read()
        res_v18 = self.client.post(
            "/v1/admin/datasets",
            content=raw_v18,
            headers={"Content-Type": "application/json", "X-Admin-Key": ADMIN_KEY},
        )
        self.assertIn(res_v18.status_code, [400, 422])

        # Case 2: update_v16.json (older dataset_version v13)
        with open(DATA_DIR / "update_v16.json", "r", encoding="utf-8") as f:
            v16_data = json.load(f)
        res_v16 = self.client.post(
            "/v1/admin/datasets",
            json=v16_data,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertIn(res_v16.status_code, [409, 422])

        # Case 3: update_v17.json (schema_version 3 mismatch)
        with open(DATA_DIR / "update_v17.json", "r", encoding="utf-8") as f:
            v17_data = json.load(f)
        res_v17 = self.client.post(
            "/v1/admin/datasets",
            json=v17_data,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res_v17.status_code, 422)
        errors = res_v17.json()["detail"]["errors"]
        self.assertTrue(any(e["field"] == "schema_version" for e in errors))

        # Case 4: update_v15.json (Valid -> Should be accepted!)
        with open(DATA_DIR / "update_v15.json", "r", encoding="utf-8") as f:
            v15_data = json.load(f)
        res_v15 = self.client.post(
            "/v1/admin/datasets",
            json=v15_data,
            headers={"X-Admin-Key": ADMIN_KEY, "Idempotency-Key": "publish-v15-key-1"},
        )
        self.assertEqual(res_v15.status_code, 201)
        res_data = res_v15.json()
        self.assertEqual(res_data["version"], "v15")
        self.assertEqual(res_data["status"], "published")

        # Test idempotency: re-publishing with same key returns original 201
        res_v15_retry = self.client.post(
            "/v1/admin/datasets",
            json=v15_data,
            headers={"X-Admin-Key": ADMIN_KEY, "Idempotency-Key": "publish-v15-key-1"},
        )
        self.assertEqual(res_v15_retry.status_code, 201)
        self.assertEqual(res_v15_retry.json()["version"], "v15")

        # Test immutability: re-publishing without idempotency key gets 409
        res_v15_dup = self.client.post(
            "/v1/admin/datasets",
            json=v15_data,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res_v15_dup.status_code, 409)

    def test_04_validation_identifies_drug_and_field(self):
        """Validates that rejected payloads return specific errors naming the drug and field."""
        bad_payload = {
            "schema_version": 2,
            "dataset_version": "v16",
            "base_version": "v15",
            "upserts": [
                {
                    "id": "bad01",
                    "name": "BadDrug1",
                    "concentration": "0 mg/mL",
                    "route": "IV",
                    "doses": {"dog": {"min": 1, "max": 2, "unit": "mg/kg"}},
                },
                {
                    "id": "bad02",
                    "name": "BadDrug2",
                    "concentration": "10 mg/mL",
                    "route": "IM",
                    "doses": {"dog": {"min": 15, "max": 5, "unit": "mg/kg"}},
                },
            ],
        }
        res = self.client.post(
            "/v1/admin/datasets",
            json=bad_payload,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res.status_code, 422)
        errors = res.json()["detail"]["errors"]
        self.assertTrue(
            any(e["drug_id"] == "bad01" and e["field"] == "concentration" for e in errors),
            f"Expected error for bad01 concentration, got: {errors}",
        )
        self.assertTrue(
            any(e["drug_id"] == "bad02" and e["field"] == "doses.dog" for e in errors),
            f"Expected error for bad02 doses.dog, got: {errors}",
        )

    def test_05_concurrent_publish_conflict(self):
        """
        If two administrators publish from the same base version at the same time,
        the second must receive 409 Conflict.
        """
        admin_a_payload = {
            "schema_version": 2,
            "dataset_version": "v16",
            "base_version": "v15",
            "upserts": [
                {
                    "id": "d020",
                    "name": "AlphaSed",
                    "concentration": "5 mg/mL",
                    "route": "IV",
                    "doses": {"dog": {"min": 1, "max": 2, "unit": "mg/kg"}},
                }
            ],
        }
        res_a = self.client.post(
            "/v1/admin/datasets",
            json=admin_a_payload,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res_a.status_code, 201)

        # Admin B also started from base v15 and tries to publish v16
        admin_b_payload = {
            "schema_version": 2,
            "dataset_version": "v16",
            "base_version": "v15",
            "upserts": [
                {
                    "id": "d021",
                    "name": "BetaSed",
                    "concentration": "10 mg/mL",
                    "route": "IM",
                    "doses": {"dog": {"min": 2, "max": 4, "unit": "mg/kg"}},
                }
            ],
        }
        res_b = self.client.post(
            "/v1/admin/datasets",
            json=admin_b_payload,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res_b.status_code, 409)
        self.assertIn("Conflict", res_b.json()["detail"])

    def test_06_delta_combination_spanning_versions(self):
        """
        Tests GET /v1/datasets/v17?from=v14 where deltas span v14 -> v15 -> v16 -> v17.
        Ensures intermediate withdrawals and upserts combine correctly.
        """
        v17_payload = {
            "schema_version": 2,
            "dataset_version": "v17",
            "base_version": "v16",
            "withdrawn": ["d001"],
            "upserts": [
                {
                    "id": "d022",
                    "name": "GammaSed",
                    "concentration": "25 mg/mL",
                    "route": "PO",
                    "doses": {"dog": {"min": 0.5, "max": 1.0, "unit": "mg/kg"}},
                }
            ],
        }
        res_v17 = self.client.post(
            "/v1/admin/datasets",
            json=v17_payload,
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res_v17.status_code, 201)

        res_delta = self.client.get("/v1/datasets/v17?from=v14")
        self.assertEqual(res_delta.status_code, 200)
        combined_delta = res_delta.json()
        self.assertEqual(combined_delta["base_version"], "v14")
        self.assertEqual(combined_delta["dataset_version"], "v17")

        self.assertIn("d009", combined_delta["withdrawn"])
        self.assertIn("d001", combined_delta["withdrawn"])

        upsert_ids = [u["id"] for u in combined_delta["upserts"]]
        self.assertIn("d005", upsert_ids)
        self.assertIn("d007", upsert_ids)
        self.assertIn("d011", upsert_ids)
        self.assertIn("d020", upsert_ids)
        self.assertIn("d022", upsert_ids)

        sig = res_delta.headers.get("X-Payload-Signature")
        sha = res_delta.headers.get("X-Payload-SHA256")
        self.assertIsNotNone(sig)
        self.assertIsNotNone(sha)
        canonical_b = canonical_json(combined_delta)
        self.assertEqual(compute_sha256(canonical_b), sha)
        self.assertTrue(verify_data(canonical_b, sig))

    def test_07_withdraw_endpoint(self):
        """Tests POST /v1/admin/withdraw creates new version and logs withdrawal."""
        res = self.client.post(
            "/v1/admin/withdraw",
            json={"drug_id": "d006", "reason": "Corvadil recalled for inverted dose range safety issue"},
            headers={"X-Admin-Key": ADMIN_KEY},
        )
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["status"], "withdrawn")
        self.assertEqual(data["version"], "v18")
        self.assertEqual(data["withdrawn_drug"], "d006")

        res_w = self.client.get("/v1/withdrawals")
        self.assertEqual(res_w.status_code, 200)
        items = res_w.json()
        self.assertTrue(any(w["drug_id"] == "d006" for w in items))

    def test_08_calc_logs_deduplication(self):
        """Tests POST /v1/calc_logs idempotently handles repeated uploads."""
        calc_record = {
            "calc_id": "calc-test-uuid-001",
            "device_id": "device-alpha",
            "dataset_version": "v15",
            "drug_id": "d001",
            "species": "dog",
            "weight_kg": 25.0,
            "inputs": {"dose": 5.0, "unit": "mg/kg"},
            "result": {"dose_mg": 125.0, "volume_ml": 2.5},
        }

        # First upload
        res1 = self.client.post("/v1/calc_logs", json=calc_record)
        self.assertEqual(res1.status_code, 200)
        self.assertEqual(res1.json()["accepted"], 1)
        self.assertEqual(res1.json()["duplicates_skipped"], 0)

        # Duplicate upload
        res2 = self.client.post("/v1/calc_logs", json=calc_record)
        self.assertEqual(res2.status_code, 200)
        self.assertEqual(res2.json()["accepted"], 0)
        self.assertEqual(res2.json()["duplicates_skipped"], 1)

    def test_09_chaos_mode_simulation(self):
        """Tests server chaos mode injections."""
        # 1. Tampered payload
        res_tampered = self.client.get("/v1/datasets/v14?chaos_inject=tampered")
        sig = res_tampered.headers.get("X-Payload-Signature")
        self.assertFalse(
            verify_data(res_tampered.content, sig),
            "Tampered payload must fail cryptographic signature verification",
        )

        # 2. Corrupted checksum
        res_bad_sha = self.client.get("/v1/datasets/v14?chaos_inject=checksum")
        sha_hdr = res_bad_sha.headers.get("X-Payload-SHA256")
        real_sha = compute_sha256(res_bad_sha.content)
        self.assertNotEqual(sha_hdr, real_sha, "Checksum header must not match actual payload sha256")

        # 3. Truncated response
        res_trunc = self.client.get("/v1/datasets/v14?chaos_inject=truncated")
        with self.assertRaises(json.JSONDecodeError):
            json.loads(res_trunc.content.decode("utf-8"))

        # 4. Server error
        res_err = self.client.get("/v1/datasets/v14?chaos_inject=server_error")
        self.assertEqual(res_err.status_code, 500)


if __name__ == "__main__":
    unittest.main()

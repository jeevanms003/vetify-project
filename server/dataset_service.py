import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import select

from .models import DatasetVersion, Withdrawal
from .crypto_service import canonical_json, sign_data
from .validator import parse_version_number

DATA_DIR = Path(__file__).resolve().parent / "data"
BASE_V14_PATH = DATA_DIR / "v14_base.json"


def compute_sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seed_v14_if_needed(db: Session) -> DatasetVersion:
    """Seeds v14 base version from v14_base.json if dataset_versions is empty."""
    v14_record = db.query(DatasetVersion).filter(DatasetVersion.version == "v14").first()
    if v14_record:
        return v14_record

    with open(BASE_V14_PATH, "r", encoding="utf-8") as f:
        v14_data = json.load(f)

    payload_bytes = canonical_json(v14_data)
    sha256_hash = compute_sha256(payload_bytes)
    signature = sign_data(payload_bytes)

    version_record = DatasetVersion(
        version="v14",
        version_num=14,
        schema_version=v14_data.get("schema_version", 2),
        base_version=None,
        parent_version=None,
        payload_json=json.dumps(v14_data),
        delta_json=None,
        sha256=sha256_hash,
        signature=signature,
    )
    db.add(version_record)
    db.commit()
    db.refresh(version_record)
    return version_record


def get_latest_version(db: Session) -> Optional[DatasetVersion]:
    return db.query(DatasetVersion).order_by(DatasetVersion.version_num.desc()).first()


def apply_delta_to_snapshot(base_snapshot: Dict[str, Any], delta: Dict[str, Any], new_version: str) -> Dict[str, Any]:
    """
    Applies withdrawn and upserts from delta to base_snapshot to produce new snapshot.
    """
    base_drugs = {d["id"]: d for d in base_snapshot.get("drugs", [])}

    withdrawn = set(delta.get("withdrawn", []))
    for drug_id in withdrawn:
        base_drugs.pop(drug_id, None)

    for drug in delta.get("upserts", []):
        base_drugs[drug["id"]] = drug

    sorted_drugs = sorted(base_drugs.values(), key=lambda d: d.get("id", ""))

    return {
        "schema_version": delta.get("schema_version", 2),
        "dataset_version": new_version,
        "drugs": sorted_drugs,
    }


def combine_deltas(db: Session, from_version: str, to_version: str) -> Optional[Dict[str, Any]]:
    """
    Combines deltas from `from_version` to `to_version`.
    Returns combined delta dict or None if not possible.
    """
    from_num = parse_version_number(from_version)
    to_num = parse_version_number(to_version)
    if from_num is None or to_num is None or from_num >= to_num:
        return None

    # Retrieve all versions in range (from_num, to_num] ordered by version_num asc
    versions = (
        db.query(DatasetVersion)
        .filter(DatasetVersion.version_num > from_num, DatasetVersion.version_num <= to_num)
        .order_by(DatasetVersion.version_num.asc())
        .all()
    )

    if not versions or versions[-1].version_num != to_num:
        return None

    # Check continuity: each version must follow the previous
    expected = from_num + 1
    for v in versions:
        if v.version_num != expected:
            return None  # gap in versions
        expected += 1

    combined_withdrawn = set()
    combined_upserts: Dict[str, Dict[str, Any]] = {}

    for v in versions:
        if not v.delta_json:
            return None  # missing delta for intermediate step
        delta = json.loads(v.delta_json)

        for w_id in delta.get("withdrawn", []):
            combined_withdrawn.add(w_id)
            combined_upserts.pop(w_id, None)

        for up in delta.get("upserts", []):
            up_id = up["id"]
            combined_upserts[up_id] = up
            combined_withdrawn.discard(up_id)

    sorted_upserts = sorted(combined_upserts.values(), key=lambda d: d.get("id", ""))
    sorted_withdrawn = sorted(list(combined_withdrawn))

    return {
        "schema_version": 2,
        "dataset_version": to_version,
        "base_version": from_version,
        "withdrawn": sorted_withdrawn,
        "upserts": sorted_upserts,
    }

import json
import os
import random
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional
from fastapi import FastAPI, Header, Query, Request, Response, HTTPException, Depends, status
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text

from .database import engine, Base, get_db, SessionLocal
from .models import DatasetVersion, IdempotencyRecord, CalculationLog, Withdrawal
from .crypto_service import (
    canonical_json,
    sign_data,
    verify_data,
    get_public_key_hex,
)
from .validator import (
    validate_dataset_payload,
    parse_version_number,
)
from .dataset_service import (
    seed_v14_if_needed,
    get_latest_version,
    apply_delta_to_snapshot,
    combine_deltas,
    compute_sha256,
)

Base.metadata.create_all(bind=engine)

ADMIN_KEY = os.environ.get("ADMIN_KEY", "vetify-secret-admin-key-2026")
CHAOS_MODE = os.environ.get("CHAOS", "0") == "1"


@asynccontextmanager
async def lifespan(app: FastAPI):
    db = SessionLocal()
    try:
        seed_v14_if_needed(db)
    finally:
        db.close()
    yield


app = FastAPI(
    title="Vetifi Drug Dataset Server",
    version="1.0.0",
    description="Dataset publishing, manifest, sync and calculation telemetry server",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def apply_chaos_if_active(request: Request, body_bytes: bytes, headers: dict) -> Response:
    inject = request.query_params.get("chaos_inject")
    should_chaos = CHAOS_MODE or (inject is not None)

    if not should_chaos:
        return Response(content=body_bytes, media_type="application/json", headers=headers)

    choice = inject if inject in ["tampered", "checksum", "truncated", "server_error"] else random.choice(
        ["tampered", "checksum", "truncated", "server_error", "normal"]
    )

    if choice == "server_error":
        raise HTTPException(status_code=500, detail="Chaos: Internal Server Error injected")
    elif choice == "truncated":
        cutoff = max(1, len(body_bytes) // 2)
        return Response(content=body_bytes[:cutoff], media_type="application/json", headers=headers)
    elif choice == "checksum":
        corrupted_headers = dict(headers)
        corrupted_headers["X-Payload-SHA256"] = "0000000000000000000000000000000000000000000000000000000000000000"
        corrupted_headers["ETag"] = '"0000000000000000000000000000000000000000000000000000000000000000"'
        return Response(content=body_bytes, media_type="application/json", headers=corrupted_headers)
    elif choice == "tampered":
        tampered = bytearray(body_bytes)
        if len(tampered) > 10:
            tampered[10] = ord("X") if tampered[10] != ord("X") else ord("Y")
        return Response(content=bytes(tampered), media_type="application/json", headers=headers)

    return Response(content=body_bytes, media_type="application/json", headers=headers)


@app.get("/health")
def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        seed_v14_if_needed(db)
        latest = get_latest_version(db)
        return {
            "status": "healthy",
            "database": "connected",
            "latest_version": latest.version if latest else None,
            "chaos_mode": CHAOS_MODE,
            "public_key_hex": get_public_key_hex(),
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database check failed: {str(e)}")


@app.get("/v1/crypto/public-key")
def get_public_key():
    return {
        "public_key_hex": get_public_key_hex(),
        "algorithm": "Ed25519",
    }


@app.get("/v1/manifest")
def get_manifest(
    request: Request,
    schema: int = Query(2, description="Client schema version"),
    current: Optional[str] = Query(None, description="Client current dataset version"),
    if_none_match: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    if schema != 2:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported schema version: {schema}. Server currently serves schema 2.",
        )

    seed_v14_if_needed(db)
    latest = get_latest_version(db)
    if not latest:
        raise HTTPException(status_code=404, detail="No dataset version available.")

    delta_available = False
    payload_to_serve: bytes
    payload_sha: str
    payload_sig: str

    if current and current != latest.version:
        combined = combine_deltas(db, current, latest.version)
        if combined is not None:
            delta_available = True
            payload_to_serve = canonical_json(combined)
            payload_sha = compute_sha256(payload_to_serve)
            payload_sig = sign_data(payload_to_serve)
        else:
            snapshot_dict = json.loads(latest.payload_json)
            payload_to_serve = canonical_json(snapshot_dict)
            payload_sha = latest.sha256
            payload_sig = latest.signature
    else:
        snapshot_dict = json.loads(latest.payload_json)
        payload_to_serve = canonical_json(snapshot_dict)
        payload_sha = latest.sha256
        payload_sig = latest.signature

    etag_value = f'"{latest.version}-{payload_sha[:16]}"'

    if if_none_match and if_none_match.strip() == etag_value:
        return Response(status_code=304)

    manifest_data = {
        "schema_version": 2,
        "latest_version": latest.version,
        "current_client_version": current,
        "delta_available": delta_available,
        "payload_size": len(payload_to_serve),
        "payload_sha256": payload_sha,
        "payload_signature": payload_sig,
    }

    manifest_bytes = canonical_json(manifest_data)
    manifest_sig = sign_data(manifest_bytes)

    headers = {
        "ETag": etag_value,
        "X-Manifest-Signature": manifest_sig,
        "Cache-Control": "no-cache",
    }

    return apply_chaos_if_active(request, manifest_bytes, headers)


@app.get("/v1/datasets/{version}")
def get_dataset(
    version: str,
    request: Request,
    from_base: Optional[str] = Query(None, alias="from", description="Base version for delta"),
    if_none_match: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    seed_v14_if_needed(db)
    target = db.query(DatasetVersion).filter(DatasetVersion.version == version).first()
    if not target:
        raise HTTPException(status_code=404, detail=f"Dataset version '{version}' not found")

    payload_dict: Dict[str, Any]
    if from_base:
        if from_base == version:
            return Response(status_code=304)
        delta_dict = combine_deltas(db, from_base, version)
        if delta_dict is not None:
            payload_dict = delta_dict
        else:
            payload_dict = json.loads(target.payload_json)
    else:
        payload_dict = json.loads(target.payload_json)

    body_bytes = canonical_json(payload_dict)
    body_sha = compute_sha256(body_bytes)
    body_sig = sign_data(body_bytes)
    etag_value = f'"{body_sha}"'

    if if_none_match and if_none_match.strip() == etag_value:
        return Response(status_code=304)

    headers = {
        "ETag": etag_value,
        "X-Payload-SHA256": body_sha,
        "X-Payload-Signature": body_sig,
        "Content-Type": "application/json",
    }

    return apply_chaos_if_active(request, body_bytes, headers)


@app.post("/v1/admin/datasets", status_code=201)
async def publish_dataset(
    request: Request,
    x_admin_key: Optional[str] = Header(None),
    idempotency_key: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    if not x_admin_key or x_admin_key != ADMIN_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized: invalid or missing X-Admin-Key")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid JSON body")

    if not isinstance(payload, dict):
        raise HTTPException(status_code=422, detail="Payload must be a JSON object")

    # 1. Check Idempotency Key
    if idempotency_key:
        cached = (
            db.query(IdempotencyRecord)
            .filter(IdempotencyRecord.idempotency_key == idempotency_key)
            .first()
        )
        if cached:
            return JSONResponse(
                status_code=cached.status_code,
                content=json.loads(cached.response_json),
            )

    # 2. Get current latest version
    seed_v14_if_needed(db)
    latest = get_latest_version(db)
    current_latest_version = latest.version if latest else None

    # 3. Validate payload schema & contents
    is_valid, validation_errors = validate_dataset_payload(payload, current_schema_version=2)
    if not is_valid:
        raise HTTPException(
            status_code=422,
            detail={"message": "Dataset validation failed", "errors": validation_errors},
        )

    new_version_str = payload.get("dataset_version")
    new_num = parse_version_number(new_version_str)

    # 4. Check for concurrency & version conflicts (HTTP 409)
    if latest and new_num is not None and new_num <= latest.version_num:
        raise HTTPException(
            status_code=409,
            detail=f"Conflict: target version '{new_version_str}' is not strictly greater than current latest '{latest.version}'. Published versions are immutable.",
        )

    base_v = payload.get("base_version")
    if base_v and base_v != current_latest_version:
        raise HTTPException(
            status_code=409,
            detail=f"Conflict: base_version '{base_v}' does not match current latest version '{current_latest_version}'. Another admin may have published an update.",
        )

    existing_ver = db.query(DatasetVersion).filter(DatasetVersion.version == new_version_str).first()
    if existing_ver:
        raise HTTPException(
            status_code=409,
            detail=f"Conflict: version '{new_version_str}' has already been published and cannot be modified.",
        )

    # 5. Apply delta or use full snapshot
    if "drugs" in payload:
        new_snapshot = payload
        delta_to_store = None
    else:
        latest_snapshot = json.loads(latest.payload_json)
        new_snapshot = apply_delta_to_snapshot(latest_snapshot, payload, new_version_str)
        delta_to_store = json.dumps(payload)

    snapshot_bytes = canonical_json(new_snapshot)
    snapshot_sha = compute_sha256(snapshot_bytes)
    snapshot_sig = sign_data(snapshot_bytes)

    version_record = DatasetVersion(
        version=new_version_str,
        version_num=new_num,
        schema_version=2,
        base_version=base_v,
        parent_version=current_latest_version,
        payload_json=json.dumps(new_snapshot),
        delta_json=delta_to_store,
        sha256=snapshot_sha,
        signature=snapshot_sig,
    )
    db.add(version_record)

    response_body = {
        "status": "published",
        "version": new_version_str,
        "parent_version": current_latest_version,
        "sha256": snapshot_sha,
        "signature": snapshot_sig,
    }

    if idempotency_key:
        db.add(
            IdempotencyRecord(
                idempotency_key=idempotency_key,
                status_code=201,
                response_json=json.dumps(response_body),
            )
        )

    db.commit()
    return response_body


@app.post("/v1/admin/withdraw", status_code=201)
async def withdraw_drug(
    request: Request,
    x_admin_key: Optional[str] = Header(None),
    idempotency_key: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    if not x_admin_key or x_admin_key != ADMIN_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized: invalid or missing X-Admin-Key")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid JSON body")

    if idempotency_key:
        cached = (
            db.query(IdempotencyRecord)
            .filter(IdempotencyRecord.idempotency_key == idempotency_key)
            .first()
        )
        if cached:
            return JSONResponse(status_code=cached.status_code, content=json.loads(cached.response_json))

    drug_id = payload.get("drug_id")
    reason = payload.get("reason", "Clinically contraindicated or safety notice")
    base_version = payload.get("base_version")

    if not drug_id or not isinstance(drug_id, str):
        raise HTTPException(status_code=400, detail="drug_id is required")

    seed_v14_if_needed(db)
    latest = get_latest_version(db)
    if not latest:
        raise HTTPException(status_code=404, detail="No active dataset version found")

    if base_version and base_version != latest.version:
        raise HTTPException(
            status_code=409,
            detail=f"Conflict: base_version '{base_version}' does not match current latest '{latest.version}'",
        )

    next_ver_num = latest.version_num + 1
    next_version_str = f"v{next_ver_num}"

    delta_payload = {
        "schema_version": 2,
        "dataset_version": next_version_str,
        "base_version": latest.version,
        "withdrawn": [drug_id],
        "upserts": [],
    }

    latest_snapshot = json.loads(latest.payload_json)
    new_snapshot = apply_delta_to_snapshot(latest_snapshot, delta_payload, next_version_str)

    snapshot_bytes = canonical_json(new_snapshot)
    snapshot_sha = compute_sha256(snapshot_bytes)
    snapshot_sig = sign_data(snapshot_bytes)

    version_record = DatasetVersion(
        version=next_version_str,
        version_num=next_ver_num,
        schema_version=2,
        base_version=latest.version,
        parent_version=latest.version,
        payload_json=json.dumps(new_snapshot),
        delta_json=json.dumps(delta_payload),
        sha256=snapshot_sha,
        signature=snapshot_sig,
    )
    db.add(version_record)

    db.add(
        Withdrawal(
            drug_id=drug_id,
            reason=reason,
            version=next_version_str,
        )
    )

    resp_body = {
        "status": "withdrawn",
        "version": next_version_str,
        "withdrawn_drug": drug_id,
        "reason": reason,
    }

    if idempotency_key:
        db.add(
            IdempotencyRecord(
                idempotency_key=idempotency_key,
                status_code=201,
                response_json=json.dumps(resp_body),
            )
        )

    db.commit()
    return resp_body


@app.post("/v1/calc_logs", status_code=200)
async def upload_calc_logs(
    request: Request,
    db: Session = Depends(get_db),
):
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid JSON body")

    records = body if isinstance(body, list) else [body]
    accepted = 0
    skipped = 0

    for rec in records:
        if not isinstance(rec, dict):
            continue
        calc_id = rec.get("calc_id")
        if not calc_id:
            continue

        existing = db.query(CalculationLog).filter(CalculationLog.calc_id == str(calc_id)).first()
        if existing:
            skipped += 1
            continue

        log_entry = CalculationLog(
            calc_id=str(calc_id),
            device_id=rec.get("device_id"),
            dataset_version=rec.get("dataset_version", "unknown"),
            drug_id=rec.get("drug_id"),
            species=rec.get("species"),
            weight_kg=float(rec.get("weight_kg")) if rec.get("weight_kg") is not None else None,
            result_json=json.dumps(rec),
        )
        db.add(log_entry)
        accepted += 1

    db.commit()
    return {
        "status": "success",
        "accepted": accepted,
        "duplicates_skipped": skipped,
        "total_processed": len(records),
    }


@app.get("/v1/withdrawals")
def list_withdrawals(db: Session = Depends(get_db)):
    items = db.query(Withdrawal).all()
    return [{"drug_id": w.drug_id, "reason": w.reason, "version": w.version} for w in items]

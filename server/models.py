from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Text, DateTime, ForeignKey, Index
from .database import Base


class DatasetVersion(Base):
    __tablename__ = "dataset_versions"

    version = Column(String(50), primary_key=True, index=True)
    version_num = Column(Integer, nullable=False, index=True)
    schema_version = Column(Integer, nullable=False, default=2)
    base_version = Column(String(50), nullable=True)
    parent_version = Column(String(50), nullable=True)
    payload_json = Column(Text, nullable=False)
    delta_json = Column(Text, nullable=True)
    sha256 = Column(String(64), nullable=False)
    signature = Column(String(128), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"

    idempotency_key = Column(String(128), primary_key=True, index=True)
    status_code = Column(Integer, nullable=False)
    response_json = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)


class CalculationLog(Base):
    __tablename__ = "calculation_logs"

    calc_id = Column(String(128), primary_key=True, index=True)
    device_id = Column(String(128), nullable=True)
    dataset_version = Column(String(50), nullable=False)
    drug_id = Column(String(50), nullable=True)
    species = Column(String(50), nullable=True)
    weight_kg = Column(Float, nullable=True)
    result_json = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)


class Withdrawal(Base):
    __tablename__ = "withdrawals"

    id = Column(Integer, primary_key=True, autoincrement=True)
    drug_id = Column(String(50), nullable=False, index=True)
    reason = Column(Text, nullable=False)
    version = Column(String(50), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

import base64
import json
import os
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

KEY_DIR = Path(__file__).resolve().parent / "keys"
PRIVATE_KEY_PATH = KEY_DIR / "ed25519_private.pem"
PUBLIC_KEY_PATH = KEY_DIR / "ed25519_public.pem"


def get_or_create_keypair():
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    if PRIVATE_KEY_PATH.exists() and PUBLIC_KEY_PATH.exists():
        with open(PRIVATE_KEY_PATH, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)
        with open(PUBLIC_KEY_PATH, "rb") as f:
            public_key = serialization.load_pem_public_key(f.read())
        return private_key, public_key

    # Generate new Ed25519 key pair
    private_key = ed25519.Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    priv_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    with open(PRIVATE_KEY_PATH, "wb") as f:
        f.write(priv_pem)
    with open(PUBLIC_KEY_PATH, "wb") as f:
        f.write(pub_pem)

    return private_key, public_key


def sign_data(data: bytes) -> str:
    """Signs bytes with Ed25519 private key and returns base64 string."""
    private_key, _ = get_or_create_keypair()
    signature = private_key.sign(data)
    return base64.b64encode(signature).decode("utf-8")


def verify_data(data: bytes, signature_b64: str) -> bool:
    """Verifies signature using the public key."""
    try:
        _, public_key = get_or_create_keypair()
        sig = base64.b64decode(signature_b64)
        public_key.verify(sig, data)
        return True
    except Exception:
        return False


def get_public_key_hex() -> str:
    """Returns 32-byte raw public key in hex format for easy client configuration."""
    _, public_key = get_or_create_keypair()
    raw = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return raw.hex()


def canonical_json(obj: dict) -> bytes:
    """Returns sorted, compact canonical JSON bytes for deterministic hashing and signing."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")

#!/usr/bin/env python3
"""Issue and verify offline DissectMyMac Pro license keys (Ed25519).

    pip install cryptography

    # once: create your signing key pair. Keep the private key SECRET (password manager / CI secret).
    python3 scripts/license_tool.py keygen

    # per sale (or from a Lemon Squeezy / Paddle webhook):
    DMM_PRIVATE_KEY=<base64> python3 scripts/license_tool.py issue --email buyer@example.com --order 1234

    python3 scripts/license_tool.py verify --public-key <base64> DMM1-...

Paste the printed public key into `LicenseVerifier.productionPublicKey`.
"""
import argparse
import base64
import datetime
import json
import os
import sys

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

PREFIX = "DMM1-"
PRODUCT = "dissectmymac-pro"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def raw_public(key: Ed25519PublicKey) -> bytes:
    return key.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def keygen(_args):
    private = Ed25519PrivateKey.generate()
    raw_private = private.private_bytes(
        serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()
    )
    print("PRIVATE (keep secret):", base64.b64encode(raw_private).decode())
    print("PUBLIC  (ship in app):", base64.b64encode(raw_public(private.public_key())).decode())


def issue_key(private_b64: str, email: str, order: str | None = None, issued: str | None = None) -> str:
    private = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_b64))
    payload = {"email": email, "product": PRODUCT, "issued": issued or datetime.date.today().isoformat()}
    if order:
        payload["order"] = order
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    return PREFIX + b64url(data) + "." + b64url(private.sign(data))


def issue(args):
    private_b64 = args.private_key or os.environ.get("DMM_PRIVATE_KEY")
    if not private_b64:
        sys.exit("Provide --private-key or set DMM_PRIVATE_KEY")
    print(issue_key(private_b64, args.email, args.order, args.issued))


def verify(args):
    public = Ed25519PublicKey.from_public_bytes(base64.b64decode(args.public_key))
    if not args.key.startswith(PREFIX):
        sys.exit("malformed")
    payload_b64, signature_b64 = args.key[len(PREFIX):].split(".")
    payload = b64url_decode(payload_b64)
    try:
        public.verify(b64url_decode(signature_b64), payload)
    except InvalidSignature:
        sys.exit("INVALID signature")
    print("VALID", json.loads(payload))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(required=True)
    sub.add_parser("keygen").set_defaults(func=keygen)
    p = sub.add_parser("issue")
    p.add_argument("--email", required=True)
    p.add_argument("--order")
    p.add_argument("--issued", help="YYYY-MM-DD (default: today)")
    p.add_argument("--private-key")
    p.set_defaults(func=issue)
    v = sub.add_parser("verify")
    v.add_argument("--public-key", required=True)
    v.add_argument("key")
    v.set_defaults(func=verify)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

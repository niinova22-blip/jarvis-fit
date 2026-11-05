"""App Store Connect API helper for CI signing and TestFlight setup.

Creates a short-lived Apple Distribution certificate and an App Store provisioning profile for
one CI run, and removes both afterwards, so no signing identity is ever stored in the repository.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (contents of the .p8 file), BUNDLE_ID.

  python scripts/asc_signing.py create  <out-dir>   # cert.p12, profile.mobileprovision, signing.json
  python scripts/asc_signing.py cleanup <out-dir>   # deletes the profile, revokes the certificate
  python scripts/asc_signing.py testflight          # ensures an internal group that gets every build
"""
import base64
import json
import os
import pathlib
import secrets
import sys
import time
import urllib.error
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
INTERNAL_GROUP = "Strengthspan Internal"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1_200, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def request(method: str, path: str, body: dict | None = None, tolerate: int | None = None) -> dict | None:
    """Calls the API; exits on errors, except `tolerate` (an HTTP status), which returns None."""
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        if error.code == tolerate:
            return None
        sys.exit(f"::error::App Store Connect API {method} {path} failed ({error.code}): {detail}")


def bundle_id_resource(identifier: str) -> str:
    result = request("GET", f"/bundleIds?filter[identifier]={identifier}&limit=200")
    for item in result.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    sys.exit(f"::error::Bundle ID {identifier} is not registered")


def create(out: pathlib.Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Strengthspan CI")]))
        .sign(key, hashes.SHA256())
    )
    csr_b64 = base64.b64encode(csr.public_bytes(serialization.Encoding.DER)).decode()

    # The team already holds the maximum number of Apple Distribution certificates (other projects'
    # CI); an iOS Distribution certificate signs App Store builds the same way and has a free slot.
    certificate = request("POST", "/certificates", {"data": {
        "type": "certificates",
        "attributes": {"certificateType": "IOS_DISTRIBUTION", "csrContent": csr_b64},
    }})["data"]
    cert_der = base64.b64decode(certificate["attributes"]["certificateContent"])
    cert = x509.load_der_x509_certificate(cert_der)

    profile_name = f"Strengthspan AppStore CI {os.environ.get('GITHUB_RUN_ID', int(time.time()))}"
    profile = request("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource(os.environ["BUNDLE_ID"])}},
            "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
        },
    }})["data"]

    password = secrets.token_hex(16)
    # Legacy PKCS#12 algorithms so `security import` accepts the file on every macOS version.
    encryption = (
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50_000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode())
    )
    (out / "cert.p12").write_bytes(pkcs12.serialize_key_and_certificates(b"strengthspan-ci", key, cert, None, encryption))
    (out / "profile.mobileprovision").write_bytes(base64.b64decode(profile["attributes"]["profileContent"]))
    (out / "signing.json").write_text(json.dumps({
        "certificateId": certificate["id"],
        "profileId": profile["id"],
        "profileName": profile_name,
        "profileUUID": profile["attributes"]["uuid"],
        "password": password,
    }))
    print(f"Created certificate {certificate['id']} and profile '{profile_name}'")


def cleanup(out: pathlib.Path) -> None:
    info_path = out / "signing.json"
    if not info_path.exists():
        print("Nothing to clean up")
        return
    info = json.loads(info_path.read_text())
    request("DELETE", f"/profiles/{info['profileId']}")
    request("DELETE", f"/certificates/{info['certificateId']}")
    for name in ("cert.p12", "profile.mobileprovision", "signing.json"):
        (out / name).unlink(missing_ok=True)
    print("Removed the CI profile and revoked the CI certificate")


def testflight() -> None:
    """Ensures an internal TestFlight group with access to all builds, containing every team member."""
    apps = request("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")["data"]
    if not apps:
        sys.exit("::error::App record not found in App Store Connect")
    app_id = apps[0]["id"]

    groups = request("GET", f"/apps/{app_id}/betaGroups?limit=200")["data"]
    group = next((g for g in groups if g["attributes"]["isInternalGroup"] and g["attributes"]["name"] == INTERNAL_GROUP), None)
    if group is None:
        group = request("POST", "/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": INTERNAL_GROUP, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})["data"]
        print(f"Created internal TestFlight group '{INTERNAL_GROUP}'")

    existing = {t["attributes"]["email"].lower() for t in request("GET", f"/betaGroups/{group['id']}/betaTesters?limit=200")["data"] if t["attributes"].get("email")}
    skipped = 0
    for user in request("GET", "/users?limit=200")["data"]:
        email = user["attributes"]["username"]
        if email.lower() in existing:
            continue
        # 409 STATE_ERROR: this member's role or app access does not allow internal testing.
        added = request("POST", "/betaTesters", {"data": {
            "type": "betaTesters",
            "attributes": {
                "email": email,
                "firstName": user["attributes"].get("firstName") or "Team",
                "lastName": user["attributes"].get("lastName") or "Member",
            },
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
        }}, tolerate=409)
        if added is None:
            skipped += 1
            continue
        print("Added a team member to the internal group")
    if skipped:
        print(f"::warning::{skipped} team member(s) cannot be internal testers (role or app access)")
    print("Internal TestFlight group is ready")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "create":
        create(pathlib.Path(sys.argv[2]))
    elif command == "cleanup":
        cleanup(pathlib.Path(sys.argv[2]))
    elif command == "testflight":
        testflight()
    else:
        sys.exit(__doc__)

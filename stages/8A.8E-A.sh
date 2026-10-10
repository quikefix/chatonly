#!/usr/bin/env bash
set -euo pipefail
APP=/opt/quikefix-edge/controller/main.py
ENV=/etc/quikefix-edge/controller.env
VENV=/opt/quikefix-edge/controller/venv
EXPECTED=411d486439c5258de8632e49c608677b4764cb2449080dd970dfa586f85f5ef8

echo '======================================================'
echo ' QUIKEFIX EDGE - STAGE 8A.8E-A'
echo ' ENCRYPTION ENGINE INTEGRITY VALIDATION'
echo '======================================================'

systemctl is-active --quiet quikefix-edge.service
curl -fsS http://127.0.0.1:8080/health; echo
echo "$EXPECTED  $APP" | sha256sum -c -
"$VENV/bin/python" -m py_compile "$APP"
grep -q 'AESGCM' "$APP"
grep -q '_encrypt_device_access_credential' "$APP"
grep -q '@app.post("/api/v1/credentials/root")' "$APP"

MASTER="$(sed -n 's/^QF_EDGE_CREDENTIAL_MASTER_KEY=//p' "$ENV" | head -n1)"
[ -n "$MASTER" ] || { echo 'ERROR: master key missing'; exit 1; }
QF_EDGE_TEST_MASTER_KEY="$MASTER" "$VENV/bin/python" <<'PY'
import os,base64,secrets
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
k=base64.b64decode(os.environ['QF_EDGE_TEST_MASTER_KEY'],validate=True)
assert len(k)==32
nonce=secrets.token_bytes(12)
aad=b'qfedge:validation:8A.8E-A'
plain=b'nonsecret-validation-payload'
ct=AESGCM(k).encrypt(nonce,plain,aad)
assert plain not in ct
assert AESGCM(k).decrypt(nonce,ct,aad)==plain
try:
    AESGCM(k).decrypt(nonce,ct,b'wrong-aad')
    raise SystemExit('ERROR: AAD rejection failed')
except Exception as exc:
    if isinstance(exc,SystemExit): raise
print('AES-256-GCM round-trip: PASS')
print('Plaintext absent from ciphertext: PASS')
print('AAD authentication rejection: PASS')
print('Master key: REDACTED')
PY
unset MASTER

echo '=== VAULT STATE ==='
DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
COUNTS="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT (SELECT COUNT(*) FROM device_access_credentials)||':'||(SELECT COUNT(*) FROM device_credential_audit);")"
unset PGPASSWORD DB_PASSWORD
echo "credential:audit = $COUNTS"
[ "$COUNTS" = '0:0' ] || { echo 'ERROR: vault unexpectedly changed'; exit 1; }

echo 'bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz' | sha256sum -c -
echo '3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump' | sha256sum -c -

echo '======================================================'
echo ' STAGE 8A.8E-A COMPLETE'
echo ' ENCRYPTION ENGINE INTEGRITY: PASS'
echo ' VAULT MODIFICATIONS: NONE'
echo '======================================================'

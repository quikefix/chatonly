#!/usr/bin/env bash
set -euo pipefail
APP=/opt/quikefix-edge/controller/main.py
ENV=/etc/quikefix-edge/controller.env
VENV=/opt/quikefix-edge/controller/venv
EXPECTED=411d486439c5258de8632e49c608677b4764cb2449080dd970dfa586f85f5ef8

echo '======================================================'
echo ' QUIKEFIX EDGE - STAGE 8A.8E PRE-FLIGHT'
echo ' AUTHENTICATED ENCRYPTED-STORAGE TEST READINESS'
echo '======================================================'

echo '=== 1. CONTROLLER ==='
systemctl is-active --quiet quikefix-edge.service
curl -fsS http://127.0.0.1:8080/health; echo

echo '=== 2. 8A.8D BASELINE ==='
echo "$EXPECTED  $APP" | sha256sum -c -
"$VENV/bin/python" -m py_compile "$APP"
grep -q '@app.post("/api/v1/credentials/root")' "$APP"
echo 'PASS: 8A.8D endpoint baseline verified'

echo '=== 3. MASTER KEY / AESGCM ==='
MASTER="$(sed -n 's/^QF_EDGE_CREDENTIAL_MASTER_KEY=//p' "$ENV" | head -n1)"
[ -n "$MASTER" ] || { echo 'ERROR: master key missing'; exit 1; }
QF_EDGE_TEST_MASTER_KEY="$MASTER" "$VENV/bin/python" <<'PY'
import os,base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
k=base64.b64decode(os.environ['QF_EDGE_TEST_MASTER_KEY'],validate=True)
assert len(k)==32
AESGCM(k)
print('AES-256-GCM: READY / KEY REDACTED')
PY
unset MASTER

echo '=== 4. VAULT STATE ==='
DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -P pager=off -c "SELECT (SELECT COUNT(*) FROM device_access_credentials) AS credentials,(SELECT COUNT(*) FROM device_credential_audit) AS audit;"
ACTIVE="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT COUNT(*) FROM device_credentials WHERE revoked_at IS NULL;")"
unset PGPASSWORD DB_PASSWORD
echo "Active enrolled device credentials: $ACTIVE"
[ "$ACTIVE" -ge 1 ] || { echo 'ERROR: no enrolled device credential available for controlled test'; exit 1; }

echo '=== 5. FROZEN 7H BASELINE ==='
echo 'bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz' | sha256sum -c -
echo '3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump' | sha256sum -c -

echo '======================================================'
echo ' STAGE 8A.8E PRE-FLIGHT COMPLETE'
echo ' READY FOR CONTROLLED AUTHENTICATED ENCRYPTION TEST'
echo ' NO PASSWORD OR DEVICE TOKEN DISPLAYED'
echo ' NO DATABASE RECORDS MODIFIED'
echo '======================================================'

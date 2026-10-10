#!/usr/bin/env bash
set -euo pipefail
ENV=/etc/quikefix-edge/controller.env
VENV=/opt/quikefix-edge/controller/venv
APP=/opt/quikefix-edge/controller/main.py

echo '======================================================'
echo ' QUIKEFIX EDGE - STAGE 8A.8D-R'
echo ' POST-PATCH VALIDATION'
echo '======================================================'

echo '=== 1. CONTROLLER ==='
systemctl is-active quikefix-edge.service
curl -fsS http://127.0.0.1:8080/health; echo

echo '=== 2. ENDPOINT + COMPILE ==='
grep -q '@app.post("/api/v1/credentials/root")' "$APP"
"$VENV/bin/python" -m py_compile "$APP"
echo 'PASS: endpoint present and controller compiles'

echo '=== 3. MASTER KEY + AES-256-GCM ==='
MASTER="$(sed -n 's/^QF_EDGE_CREDENTIAL_MASTER_KEY=//p' "$ENV" | head -n1)"
[ -n "$MASTER" ] || { echo 'ERROR: master key missing'; exit 1; }
QF_EDGE_TEST_MASTER_KEY="$MASTER" "$VENV/bin/python" <<'PY'
import os, base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
key=base64.b64decode(os.environ['QF_EDGE_TEST_MASTER_KEY'], validate=True)
if len(key)!=32: raise SystemExit('ERROR: master key is not 256-bit')
AESGCM(key)
print('Credential master key: PRESENT / 256-bit / REDACTED')
print('AES-256-GCM: READY')
PY
unset MASTER

echo '=== 4. DATABASE MUST STILL BE EMPTY ==='
DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
COUNTS="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT (SELECT COUNT(*) FROM device_access_credentials)||':'||(SELECT COUNT(*) FROM device_credential_audit);")"
unset PGPASSWORD DB_PASSWORD
echo "credential:audit = $COUNTS"
[ "$COUNTS" = '0:0' ] || { echo 'ERROR: unexpected credential records'; exit 1; }
echo 'PASS: credential vault remains empty'

echo '=== 5. SECURITY REJECTION TEST ==='
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
HTTP="$(curl -sS -o "$TMP" -w '%{http_code}' -X POST http://127.0.0.1:8080/api/v1/credentials/root -H 'Content-Type: application/json' --data '{"password":"SYNTHETIC-NONSECRET-VALIDATION-VALUE"}')"
echo "HTTP status: $HTTP"; cat "$TMP"; echo
[ "$HTTP" = '401' ] || { echo 'ERROR: unauthenticated request not rejected'; exit 1; }
echo 'PASS: authentication enforced'

echo '=== 6. CURRENT MAIN.PY HASH ==='
sha256sum "$APP"

echo '=== 7. FROZEN 7H BASELINE ==='
echo 'bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz' | sha256sum -c -
echo '3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump' | sha256sum -c -

echo '======================================================'
echo ' STAGE 8A.8D COMPLETE'
echo ' ROOT CREDENTIAL API: INSTALLED'
echo ' AES-256-GCM: VERIFIED'
echo ' DEVICE AUTHENTICATION: ENFORCED'
echo ' STORED ROOT CREDENTIALS: 0'
echo '======================================================'

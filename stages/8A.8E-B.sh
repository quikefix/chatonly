#!/usr/bin/env bash
set -euo pipefail
APP=/opt/quikefix-edge/controller/main.py
ENV=/etc/quikefix-edge/controller.env
VENV=/opt/quikefix-edge/controller/venv
EXPECTED=411d486439c5258de8632e49c608677b4764cb2449080dd970dfa586f85f5ef8

echo '======================================================'
echo ' QUIKEFIX EDGE - STAGE 8A.8E-B'
echo ' CREDENTIAL API STRUCTURAL VALIDATION'
echo '======================================================'

curl -fsS http://127.0.0.1:8080/health; echo
echo "$EXPECTED  $APP" | sha256sum -c -
"$VENV/bin/python" -m py_compile "$APP"

for needle in \
  '@app.post("/api/v1/credentials/root")' \
  'root_credential_already_registered' \
  'device_access_credentials' \
  'device_credential_audit' \
  'credential_registered' \
  'AESGCM' \
  'encryption_version'; do
  grep -q "$needle" "$APP" || { echo "ERROR: missing expected API component: $needle"; exit 1; }
done

echo 'PASS: credential API components present'

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
HTTP="$(curl -sS -o "$TMP" -w '%{http_code}' -X POST http://127.0.0.1:8080/api/v1/credentials/root -H 'Content-Type: application/json' --data '{"password":"STRUCTURAL-VALIDATION-NOT-A-REAL-PASSWORD"}')"
[ "$HTTP" = 401 ] || { echo "ERROR: expected 401, got $HTTP"; cat "$TMP"; exit 1; }
echo 'PASS: unauthenticated write rejected'

DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
COUNTS="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT (SELECT COUNT(*) FROM device_access_credentials)||':'||(SELECT COUNT(*) FROM device_credential_audit);")"
unset PGPASSWORD DB_PASSWORD
[ "$COUNTS" = '0:0' ] || { echo "ERROR: vault unexpectedly changed: $COUNTS"; exit 1; }
echo 'PASS: vault remains empty'

echo 'bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz' | sha256sum -c -
echo '3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump' | sha256sum -c -

echo '======================================================'
echo ' STAGE 8A.8E-B COMPLETE'
echo ' API STRUCTURE: PASS'
echo ' AUTH BOUNDARY: PASS'
echo ' VAULT MODIFICATIONS: NONE'
echo '======================================================'

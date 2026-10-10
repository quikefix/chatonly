#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " QUIKEFIX EDGE - STAGE 8A.8D PRE-FLIGHT"
echo " CREDENTIAL API PATCH ANCHOR VALIDATION"
echo "======================================================"

[ "$(hostname)" = "edg" ] || { echo "ERROR: Run this on edg only."; exit 1; }

APP="/opt/quikefix-edge/controller/main.py"
ENV="/etc/quikefix-edge/controller.env"
EXPECTED="f5ea9b901943025c3536a202de09edd78e711627a6a12c459166cbf4c45cc3b0"

echo
echo "=== 1. CONTROLLER HEALTH ==="
curl -fsS http://127.0.0.1:8080/health; echo

echo
echo "=== 2. MAIN.PY BASELINE ==="
echo "$EXPECTED  $APP" | sha256sum -c -

echo
echo "=== 3. REQUIRED IMPORT/INSERT ANCHORS ==="
for anchor in \
  'import base64' \
  'from datetime import datetime, timedelta, timezone' \
  '# QUIKEFIX EDGE - DEVICE INVENTORY' \
  '@app.post("/api/v1/inventory")'; do
  grep -Fq "$anchor" "$APP" || { echo "ERROR: Missing anchor: $anchor"; exit 1; }
  echo "FOUND: $anchor"
done

echo
echo "=== 4. VERIFY CREDENTIAL API DOES NOT ALREADY EXIST ==="
if grep -Fq '/api/v1/credentials/root' "$APP"; then
  echo "ERROR: Root credential API already exists. Stop for inspection."
  exit 1
fi
echo "PASS: endpoint absent"

echo
echo "=== 5. VERIFY MASTER KEY + AESGCM ==="
grep -q '^QF_EDGE_CREDENTIAL_MASTER_KEY=' "$ENV" || { echo "ERROR: Master key missing."; exit 1; }
/opt/quikefix-edge/controller/venv/bin/python - <<'PY'
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
print("AESGCM: PRESENT")
PY

echo
echo "=== 6. DATABASE TABLE COUNTS ==="
DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -P pager=off -c "SELECT (SELECT COUNT(*) FROM device_access_credentials) AS credentials, (SELECT COUNT(*) FROM device_credential_audit) AS audit;"
unset PGPASSWORD DB_PASSWORD

echo
echo "=== 7. PYTHON COMPILE ==="
/opt/quikefix-edge/controller/venv/bin/python -m py_compile "$APP"
echo "PASS: main.py compiles"

echo
echo "=== 8. FROZEN 7H BASELINE ==="
echo "bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz" | sha256sum -c -
echo "3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump" | sha256sum -c -

echo
echo "======================================================"
echo " STAGE 8A.8D PRE-FLIGHT COMPLETE"
echo " SAFE TO BUILD CONTROLLED CREDENTIAL API PATCH"
echo " NO CONTROLLER CODE MODIFIED"
echo "======================================================"

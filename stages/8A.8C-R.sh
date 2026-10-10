#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " QUIKEFIX EDGE - STAGE 8A.8C-R"
echo " COMPLETE AUTH PATTERN INSPECTION"
echo "======================================================"

if [ "$(hostname)" != "edg" ]; then
    echo "ERROR: Run this on edg only."
    exit 1
fi

APP="/opt/quikefix-edge/controller/main.py"
ENV="/etc/quikefix-edge/controller.env"
POLICY="/opt/quikefix-edge/agent/docs/PHYSICAL_SECURITY.txt"

echo
echo "=== 1. CONTROLLER HEALTH ==="
curl -fsS http://127.0.0.1:8080/health
echo

echo
echo "=== 2. VERIFY MAIN.PY UNCHANGED ==="
echo "f5ea9b901943025c3536a202de09edd78e711627a6a12c459166cbf4c45cc3b0  $APP" | sha256sum -c -

echo
echo "=== 3. ROUTES - STATIC SOURCE INSPECTION ==="
grep -nE '@app\.(get|post|put|patch|delete)\("/api/' "$APP" || true

echo
echo "=== 4. VERIFY DEVICE AUTH QUERY PATTERN ==="
AUTH_COUNT="$(grep -c 'WHERE dc.token_hash = %s' "$APP")"
echo "Device credential lookup blocks: $AUTH_COUNT"
if [ "$AUTH_COUNT" -lt 3 ]; then
    echo "ERROR: Expected existing device authentication blocks not found."
    exit 1
fi

echo
echo "=== 5. VERIFY REVOCATION CHECK ==="
REVOKE_COUNT="$(grep -c 'dc.revoked_at IS NULL' "$APP")"
echo "Active-credential checks: $REVOKE_COUNT"
if [ "$REVOKE_COUNT" -lt 3 ]; then
    echo "ERROR: Expected revoked credential protection not found."
    exit 1
fi

echo
echo "=== 6. VERIFY ACCESS CREDENTIAL TABLE EMPTY ==="
DB_HOST="$(sed -n 's/^QF_EDGE_DB_HOST=//p' "$ENV" | head -n1)"
DB_PORT="$(sed -n 's/^QF_EDGE_DB_PORT=//p' "$ENV" | head -n1)"
DB_NAME="$(sed -n 's/^QF_EDGE_DB_NAME=//p' "$ENV" | head -n1)"
DB_USER="$(sed -n 's/^QF_EDGE_DB_USER=//p' "$ENV" | head -n1)"
DB_PASSWORD="$(sed -n 's/^QF_EDGE_DB_PASSWORD=//p' "$ENV" | head -n1)"
export PGPASSWORD="$DB_PASSWORD"
ACCESS_COUNT="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc 'SELECT COUNT(*) FROM device_access_credentials;')"
AUDIT_COUNT="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc 'SELECT COUNT(*) FROM device_credential_audit;')"
echo "Stored access credentials: $ACCESS_COUNT"
echo "Credential audit records:  $AUDIT_COUNT"
[ "$ACCESS_COUNT" = "0" ] || { echo "ERROR: Unexpected access credential exists."; exit 1; }
unset PGPASSWORD DB_PASSWORD

echo
echo "=== 7. MASTER KEY STATUS ==="
if grep -q '^QF_EDGE_CREDENTIAL_MASTER_KEY=' "$ENV"; then
    echo "Credential master key: PRESENT / REDACTED"
else
    echo "ERROR: Credential master key missing."
    exit 1
fi

echo
echo "=== 8. ENCRYPTION ENGINE ==="
/opt/quikefix-edge/controller/venv/bin/python - <<'PY'
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import cryptography
print("cryptography:", cryptography.__version__)
print("AES-256-GCM capability: PRESENT")
PY

echo
echo "=== 9. PHYSICAL SECURITY POLICY ==="
[ -s "$POLICY" ] || { echo "ERROR: Physical security policy missing."; exit 1; }
for requirement in "encrypted storage" "TPM-bound disk unlocking" "Live CD/USB" "installer ISO being secret"; do
    grep -Fq "$requirement" "$POLICY"
    echo "FOUND: $requirement"
done

echo
echo "=== 10. FROZEN 7H BASELINE ==="
echo "bfc1e2ddc4da180d086aabcf579c7f1703f33432df23268b76633f22a4451db1  /root/quikefix-edge-controller-7H-20261010-171619.tar.gz" | sha256sum -c -
echo "3dae7d823afb83af4e97c31e6db57777fa39a727a72645218cc8d3c15d72367c  /root/qfedge-7H-20261010-171619.dump" | sha256sum -c -

echo
echo "=== 11. FINAL CONTROLLER HEALTH ==="
curl -fsS http://127.0.0.1:8080/health
echo

echo
echo "======================================================"
echo " STAGE 8A.8C-R COMPLETE"
echo " DEVICE AUTH PATTERN VERIFIED"
echo " CREDENTIAL VAULT READY FOR API INTEGRATION"
echo " MAIN.PY NOT MODIFIED"
echo "======================================================"

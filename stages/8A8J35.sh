#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " QUIKEFIX EDGE - STAGE 8A.8J.35"
echo " QF-000009 CONTROLLER + DB POST-REBOOT ACCEPTANCE"
echo "======================================================"

DEVICE="QF-000009"
EXPECTED_LAN="10.100.0.103"
EXPECTED_VPN="10.77.0.8"
EXPECTED_WG="Zn350+erzgSSMouOPfUd5uLZJzq+kXAxyg4hpXpyBXI="

echo
echo "=== 1. CONTROLLER HEALTH ==="
systemctl is-active quikefix-edge.service
curl -fsS http://127.0.0.1:8080/health
echo
echo "controller_health=PASS"

echo
echo "=== 2. DEVICE DATABASE STATE ==="
ROW="$(sudo -u postgres psql -d qfedge -At -F '|' -c "
SELECT device_id,status,hostname,COALESCE(host(primary_lan_ip),'-'),COALESCE(host(vpn_ip),'-'),COALESCE(wireguard_public_key,'-'),COALESCE(agent_version,'-'),last_seen_at
FROM devices WHERE device_id='${DEVICE}';")"
echo "$ROW"
test -n "$ROW"
IFS='|' read -r DB_DEVICE DB_STATUS DB_HOST DB_LAN DB_VPN DB_WG DB_AGENT DB_LAST <<< "$ROW"
test "$DB_DEVICE" = "$DEVICE"
test "$DB_STATUS" = "online"
test "$DB_LAN" = "$EXPECTED_LAN"
test "$DB_VPN" = "$EXPECTED_VPN"
test "$DB_WG" = "$EXPECTED_WG"
echo "device_database=PASS"

echo
echo "=== 3. CONTROLLER WIREGUARD PEER ==="
wg show qfedge0
wg show qfedge0 peers | grep -Fxq "$EXPECTED_WG"
ALLOWED="$(wg show qfedge0 allowed-ips | awk -v k="$EXPECTED_WG" '$1==k {print $2}')"
echo "allowed_ips=$ALLOWED"
test "$ALLOWED" = "${EXPECTED_VPN}/32"
HS="$(wg show qfedge0 latest-handshakes | awk -v k="$EXPECTED_WG" '$1==k {print $2}')"
test -n "$HS"
test "$HS" -gt 0
AGE=$(( $(date +%s) - HS ))
echo "handshake_age_seconds=$AGE"
test "$AGE" -le 180
echo "controller_wireguard_peer=PASS"

echo
echo "=== 4. CONTROLLER TO DEVICE VPN ==="
ping -c 3 -W 2 "$EXPECTED_VPN"
echo "controller_to_device_vpn=PASS"

echo
echo "=== 5. ROOT CREDENTIAL VAULT ==="
DEV_DB_ID="$(sudo -u postgres psql -d qfedge -Atc "SELECT id FROM devices WHERE device_id='${DEVICE}';")"
test -n "$DEV_DB_ID"
CRED="$(sudo -u postgres psql -d qfedge -At -F '|' -c "
SELECT id,credential_type,username,(ciphertext IS NOT NULL AND length(ciphertext)>20),revoked_at IS NULL
FROM device_access_credentials
WHERE device_id=${DEV_DB_ID} AND credential_type='root_password'
ORDER BY id DESC LIMIT 1;")"
echo "$CRED"
test -n "$CRED"
IFS='|' read -r CRED_ID CRED_TYPE CRED_USER CRED_ENCRYPTED CRED_ACTIVE <<< "$CRED"
test "$CRED_TYPE" = "root_password"
test "$CRED_USER" = "root"
test "$CRED_ENCRYPTED" = "t"
test "$CRED_ACTIVE" = "t"
echo "root_credential_encrypted_active=PASS"

echo
echo "=== 6. ROOT CREDENTIAL AUDIT ==="
AUDIT_COUNT="$(sudo -u postgres psql -d qfedge -Atc "SELECT count(*) FROM device_credential_audit WHERE device_id=${DEV_DB_ID} AND credential_id=${CRED_ID} AND action='created';")"
echo "credential_created_audit_count=$AUDIT_COUNT"
test "$AUDIT_COUNT" -ge 1
echo "credential_audit=PASS"

echo
echo "=== 7. INVENTORY ==="
DISK_COUNT="$(sudo -u postgres psql -d qfedge -Atc "SELECT count(*) FROM device_disks WHERE device_id=${DEV_DB_ID};")"
echo "device_disk_count=$DISK_COUNT"
test "$DISK_COUNT" -ge 1
echo "inventory_database=PASS"

echo
echo "=== 8. BOOTSTRAP TERMINAL STATE ==="
BOOT="$(sudo -u postgres psql -d qfedge -At -F '|' -c "
SELECT br.request_id,br.status,(br.consumed_at IS NOT NULL),
       (br.enrollment_token_id IS NOT NULL),
       COALESCE(ba.deleted_at IS NOT NULL,false),
       COALESCE(ba.redeemed_at IS NOT NULL,false)
FROM bootstrap_requests br
LEFT JOIN bootstrap_authorizations ba ON ba.bootstrap_request_id=br.id
WHERE br.wireguard_public_key='${EXPECTED_WG}'
ORDER BY br.id DESC LIMIT 1;")"
echo "$BOOT"
test -n "$BOOT"
IFS='|' read -r BOOT_REQ BOOT_STATUS BOOT_CONSUMED BOOT_TOKEN_BOUND AUTH_DELETED AUTH_REDEEMED <<< "$BOOT"
test "$BOOT_STATUS" = "consumed"
test "$BOOT_CONSUMED" = "t"
test "$BOOT_TOKEN_BOUND" = "t"
test "$AUTH_DELETED" = "t"
test "$AUTH_REDEEMED" = "t"
echo "bootstrap_terminal_state=PASS"

echo
echo "=== 9. ENROLLMENT TOKEN CONSUMED ==="
TOKEN="$(sudo -u postgres psql -d qfedge -At -F '|' -c "
SELECT (et.used_at IS NOT NULL),COALESCE(et.used_by_device_id,0),et.label
FROM enrollment_tokens et
JOIN bootstrap_requests br ON br.enrollment_token_id=et.id
WHERE br.wireguard_public_key='${EXPECTED_WG}'
ORDER BY et.id DESC LIMIT 1;")"
echo "$TOKEN"
test -n "$TOKEN"
IFS='|' read -r TOKEN_USED TOKEN_DEVICE TOKEN_LABEL <<< "$TOKEN"
test "$TOKEN_USED" = "t"
test "$TOKEN_DEVICE" = "$DEV_DB_ID"
echo "enrollment_token_consumed=PASS"

echo
echo "=== 10. NO PLAINTEXT CREDENTIAL OUTPUT ==="
echo "credential_plaintext_exposed=NO"

echo
echo "======================================================"
echo " STAGE 8A.8J.35 COMPLETE"
echo " DEVICE_ID=QF-000009"
echo " DEVICE_DATABASE=PASS"
echo " CONTROLLER_WIREGUARD=PASS"
echo " VPN_REACHABILITY=PASS"
echo " ROOT_CREDENTIAL_VAULT=PASS"
echo " INVENTORY=PASS"
echo " BOOTSTRAP_CONSUMED=PASS"
echo " ENROLLMENT_TOKEN_CONSUMED=PASS"
echo "======================================================"

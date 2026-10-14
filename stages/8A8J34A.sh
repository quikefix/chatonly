#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " QUIKEFIX EDGE - STAGE 8A.8J.34A"
echo " QF-000009 POST-REBOOT V3.1 ACCEPTANCE"
echo "======================================================"

echo
echo "=== 1. BOOT / VERSION ==="

uptime
cat /usr/local/quikefix-agent/VERSION

test "$(cat /usr/local/quikefix-agent/VERSION)" = \
"0.2.2-remote-bootstrap-wg-bound-dirfix"

echo "v31_version=PASS"

echo
echo "=== 2. DEVICE IDENTITY ==="

grep '^DEVICE_ID=QF-000009$' /etc/quikefix-edge/device.conf

test -s /etc/quikefix-edge/device.conf
test ! -e /etc/quikefix-edge/enrollment.token
test -s /etc/quikefix-edge/wireguard-private.key
test -s /var/lib/quikefix-edge/wireguard-public.key
test -e /var/lib/quikefix-edge/root-credential.registered

echo "device_identity=PASS"
echo "enrollment_token_absent=PASS"
echo "root_credential_marker=PASS"

echo
echo "=== 3. WIREGUARD INTERFACE ==="

ip -br addr show qfedge0
wg show qfedge0

ip -4 addr show qfedge0 | grep -Fq '10.77.0.8/32'

echo "vpn_address=PASS"

echo
echo "=== 4. WAIT FOR POST-REBOOT HANDSHAKE ==="

PASS=0

for i in $(seq 1 12); do
    HS="$(wg show qfedge0 latest-handshakes | awk '{print $2}')"
    NOW="$(date +%s)"

    if [ -n "$HS" ] && [ "$HS" -gt 0 ]; then
        AGE=$((NOW-HS))
        echo "attempt=$i handshake_age_seconds=$AGE"

        if [ "$AGE" -le 180 ]; then
            PASS=1
            break
        fi
    else
        echo "attempt=$i handshake=none"
    fi

    sleep 5
done

test "$PASS" -eq 1

echo "post_reboot_wireguard=PASS"

echo
echo "=== 5. CONTROLLER VPN REACHABILITY ==="

ping -c 3 -W 2 10.77.0.1

echo "controller_vpn=PASS"

echo
echo "=== 6. REMOTE BOOTSTRAP MUST NOT RUN AGAIN ==="

systemctl start quikefix-edge-remote-bootstrap.service || true
sleep 1

COND="$(systemctl show \
 quikefix-edge-remote-bootstrap.service \
 -p ConditionResult --value)"

echo "remote_bootstrap_condition_result=$COND"

test "$COND" = "no"

echo "remote_bootstrap_blocked=PASS"

echo
echo "=== 7. HEARTBEAT ==="

systemctl start quikefix-edge-heartbeat.service
sleep 2

journalctl \
 -u quikefix-edge-heartbeat.service \
 -b --no-pager -n 15

journalctl \
 -u quikefix-edge-heartbeat.service \
 -b --no-pager | grep -Fq 'HEARTBEAT_OK'

echo "heartbeat=PASS"

echo
echo "=== 8. INVENTORY ==="

systemctl start quikefix-edge-inventory.service
sleep 2

journalctl \
 -u quikefix-edge-inventory.service \
 -b --no-pager -n 15

journalctl \
 -u quikefix-edge-inventory.service \
 -b --no-pager | grep -Fq 'INVENTORY_SYNC_OK'

echo "inventory=PASS"

echo
echo "=== 9. ROOT CREDENTIAL SYNC ==="

systemctl start quikefix-edge-root-credential.service
sleep 2

systemctl --no-pager --full status \
 quikefix-edge-root-credential.service || true

test -e /var/lib/quikefix-edge/root-credential.registered

echo "root_credential=PASS"

echo
echo "=== 10. VPN RECONCILIATION ==="

systemctl start quikefix-edge-vpn.service
sleep 2

journalctl \
 -u quikefix-edge-vpn.service \
 -b --no-pager -n 15

journalctl \
 -u quikefix-edge-vpn.service \
 -b --no-pager | grep -Fq 'VPN_SYNC_OK'

echo "vpn_reconciliation=PASS"

echo
echo "=== 11. TIMERS AFTER REBOOT ==="

for t in \
 quikefix-edge-remote-bootstrap.timer \
 quikefix-edge-heartbeat.timer \
 quikefix-edge-root-credential.timer \
 quikefix-edge-inventory.timer \
 quikefix-edge-vpn.timer
do
    systemctl is-enabled "$t"
    systemctl is-active "$t"
done

echo "timers_after_reboot=PASS"

echo
echo "=== 12. FINAL WIREGUARD STATE ==="

wg show qfedge0

echo
echo "======================================================"
echo " STAGE 8A.8J.34A COMPLETE"
echo " DEVICE_ID=QF-000009"
echo " V31_REBOOT_PERSISTENCE=PASS"
echo " DEVICE_IDENTITY=PASS"
echo " WIREGUARD=PASS"
echo " CONTROLLER_VPN=PASS"
echo " HEARTBEAT=PASS"
echo " INVENTORY=PASS"
echo " ROOT_CREDENTIAL=PASS"
echo " REMOTE_REENROLLMENT_BLOCKED=PASS"
echo "======================================================"

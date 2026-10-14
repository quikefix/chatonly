#!/usr/bin/env bash
set -euo pipefail
umask 077

echo "======================================================"
echo " QUIKEFIX EDGE - STAGE 8A.8J.36"
echo " QF-000009 HAIRPIN NAT PERSISTENCE"
echo " RUN ON: pve1"
echo "======================================================"

SCRIPT="/usr/local/sbin/quikefix-edge-hairpin-nat.sh"
SERVICE="quikefix-edge-hairpin-nat.service"
CLIENT="10.100.0.103"
PUBLIC="213.133.123.58"
EDGE="10.100.0.171"
GW="10.100.0.1"
PORT="51820"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP="${SCRIPT}.before-QF000009-${STAMP}"

echo
echo "=== 1. PRECHECK ==="
test -f "$SCRIPT"
test -f "/etc/systemd/system/${SERVICE}"
systemctl is-enabled "$SERVICE"
systemctl is-active "$SERVICE"
test "$(sysctl -n net.ipv4.ip_forward)" = "1"
echo "precheck=PASS"

echo
echo "=== 2. PRESERVE EXISTING SCRIPT ==="
cp -a "$SCRIPT" "$BACKUP"
echo "backup=$BACKUP"
echo "before_sha256=$(sha256sum "$BACKUP" | awk '{print $1}')"

echo
echo "=== 3. VERIFY PROTECTED EXISTING RULE REFERENCES ==="
grep -Fq '10.100.0.214' "$SCRIPT"
grep -Fq '10.100.0.133' "$SCRIPT"
echo "protected_existing_clients=PASS"

echo
echo "=== 4. ADD QF-000009 IDEMPOTENT BLOCK IF MISSING ==="
if grep -Fq '# QF-000009 10.100.0.103' "$SCRIPT"; then
  echo "qf000009_block=ALREADY_PRESENT"
else
  cat >> "$SCRIPT" <<'EOF'

# QF-000009 10.100.0.103
iptables -t nat -C PREROUTING -i vmbr100 -s 10.100.0.103/32 -d 213.133.123.58/32 -p udp --dport 51820 -j DNAT --to-destination 10.100.0.171:51820 2>/dev/null || \
iptables -t nat -A PREROUTING -i vmbr100 -s 10.100.0.103/32 -d 213.133.123.58/32 -p udp --dport 51820 -j DNAT --to-destination 10.100.0.171:51820

iptables -t nat -C POSTROUTING -s 10.100.0.103/32 -d 10.100.0.171/32 -p udp --dport 51820 -j SNAT --to-source 10.100.0.1 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.100.0.103/32 -d 10.100.0.171/32 -p udp --dport 51820 -j SNAT --to-source 10.100.0.1

iptables -C FORWARD -s 10.100.0.103/32 -d 10.100.0.171/32 -p udp --dport 51820 -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -s 10.100.0.103/32 -d 10.100.0.171/32 -p udp --dport 51820 -j ACCEPT

iptables -C FORWARD -s 10.100.0.171/32 -d 10.100.0.103/32 -p udp -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -s 10.100.0.171/32 -d 10.100.0.103/32 -p udp -j ACCEPT
EOF
  echo "qf000009_block=ADDED"
fi
chmod 700 "$SCRIPT"
bash -n "$SCRIPT"
echo "script_syntax=PASS"

echo
echo "=== 5. VERIFY SCRIPT CONTAINS ALL REQUIRED CLIENTS ==="
grep -Fq '10.100.0.214' "$SCRIPT"
grep -Fq '10.100.0.133' "$SCRIPT"
grep -Fq '10.100.0.103' "$SCRIPT"
echo "persistent_clients=PASS"

echo
echo "=== 6. APPLY PERSISTENT SCRIPT ==="
"$SCRIPT"
systemctl restart "$SERVICE"
systemctl is-active "$SERVICE"
echo "service_apply=PASS"

echo
echo "=== 7. VERIFY QF-000009 LIVE RULES ==="
iptables -t nat -C PREROUTING -i vmbr100 -s "$CLIENT/32" -d "$PUBLIC/32" -p udp --dport "$PORT" -j DNAT --to-destination "$EDGE:$PORT"
iptables -t nat -C POSTROUTING -s "$CLIENT/32" -d "$EDGE/32" -p udp --dport "$PORT" -j SNAT --to-source "$GW"
iptables -C FORWARD -s "$CLIENT/32" -d "$EDGE/32" -p udp --dport "$PORT" -j ACCEPT
iptables -C FORWARD -s "$EDGE/32" -d "$CLIENT/32" -p udp -j ACCEPT
echo "qf000009_live_rules=PASS"

echo
echo "=== 8. IDEMPOTENCY TEST ==="
count_rules() {
  local a b c d
  a="$(iptables-save -t nat | grep -F -- "-s 10.100.0.103/32 -d 213.133.123.58/32" | grep -F -- '--dport 51820' | grep -c 'DNAT' || true)"
  b="$(iptables-save -t nat | grep -F -- "-s 10.100.0.103/32 -d 10.100.0.171/32" | grep -F -- '--dport 51820' | grep -c 'SNAT' || true)"
  c="$(iptables-save | grep -F -- "-s 10.100.0.103/32 -d 10.100.0.171/32" | grep -F -- '--dport 51820' | grep -c 'ACCEPT' || true)"
  d="$(iptables-save | grep -F -- "-s 10.100.0.171/32 -d 10.100.0.103/32" | grep -c 'ACCEPT' || true)"
  echo "$a|$b|$c|$d"
}
BEFORE="$(count_rules)"
"$SCRIPT"
AFTER="$(count_rules)"
echo "counts_before=$BEFORE"
echo "counts_after=$AFTER"
test "$BEFORE" = "$AFTER"
IFS='|' read -r A B C D <<< "$AFTER"
test "$A" -ge 1
test "$B" -ge 1
test "$C" -ge 1
test "$D" -ge 1
echo "idempotency=PASS"

echo
echo "=== 9. VERIFY EXTERNAL DNAT PRESERVED ==="
iptables-save -t nat | grep -F -- '--dport 51820' | grep -F '10.100.0.171:51820'
echo "external_dnat_present=PASS"

echo
echo "=== 10. VERIFY UNRELATED WG0 PRESERVED ==="
if ip link show wg0 >/dev/null 2>&1; then
  wg show wg0
  echo "unrelated_wg0_present=PASS"
else
  echo "unrelated_wg0_present=WARNING_NOT_FOUND"
fi

echo
echo "=== 11. FINAL SCRIPT HASH ==="
FINAL_SHA="$(sha256sum "$SCRIPT" | awk '{print $1}')"
echo "persistent_script_sha256=$FINAL_SHA"

echo
echo "=== 12. SERVICE STATUS ==="
systemctl --no-pager --full status "$SERVICE" || true

echo
echo "======================================================"
echo " STAGE 8A.8J.36 COMPLETE"
echo " QF-000009_HAIRPIN_PERSISTED=YES"
echo " PROTECTED_EXISTING_CLIENTS=PASS"
echo " IDEMPOTENCY=PASS"
echo " SERVICE=ACTIVE"
echo " SCRIPT_SHA256=$FINAL_SHA"
echo " BACKUP=$BACKUP"
echo "======================================================"

#!/bin/bash
set -euo pipefail

BASE=/root/qf-edge-iso
OUT="$BASE/quikefix-first-boot"
AGENT="$BASE/quikefix-edge-agent-8A8J-ZEROTOUCH-V3.1-FINAL.tar.gz"
DEBS="$BASE/offline-debs"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

AGENT_SHA=a8987927cba6a4f757398bbf13e6f724b806df311a2cec3f1c245fa4c7d2fb27
JQ_SHA=7350392f700e20e46b7ae174a57f54e4ea106dd559753646d629b4e618bf2bff
LIBJQ_SHA=70bb2cbd66d5ada4349067ae9f61d0560b3b359d4203f2c051ca5773153ae0ba
ONIG_SHA=3abee130696244050500bcc7870e3b4cb82ddd87149ece3fd55010c3d4e1d18c
WG_SHA=4fc58e193786a86465596c83ebfc10bfcb5241b918e9a4b60113f62e98046fe1

JQ="$DEBS/jq_1.7.1-6+deb13u4_amd64.deb"
LIBJQ="$DEBS/libjq1_1.7.1-6+deb13u4_amd64.deb"
ONIG="$DEBS/libonig5_6.9.9-1+b1_amd64.deb"
WG="$DEBS/wireguard-tools_1.0.20210914-3_amd64.deb"

for f in "$AGENT" "$JQ" "$LIBJQ" "$ONIG" "$WG"; do test -f "$f" || { echo "MISSING: $f"; exit 1; }; done
printf '%s  %s\n' "$AGENT_SHA" "$AGENT" | sha256sum -c -
printf '%s  %s\n' "$JQ_SHA" "$JQ" | sha256sum -c -
printf '%s  %s\n' "$LIBJQ_SHA" "$LIBJQ" | sha256sum -c -
printf '%s  %s\n' "$ONIG_SHA" "$ONIG" | sha256sum -c -
printf '%s  %s\n' "$WG_SHA" "$WG" | sha256sum -c -

mkdir -p "$WORK/payload/offline-debs"
cp "$AGENT" "$WORK/payload/agent.tar.gz"
cp "$ONIG" "$WORK/payload/offline-debs/libonig5.deb"
cp "$LIBJQ" "$WORK/payload/offline-debs/libjq1.deb"
cp "$JQ" "$WORK/payload/offline-debs/jq.deb"
cp "$WG" "$WORK/payload/offline-debs/wireguard-tools.deb"
tar -C "$WORK/payload" -czf "$WORK/payload.tar.gz" .

cat > "$OUT" <<'SCRIPT'
#!/bin/bash
set -eu
umask 077
[ "$(id -u)" -eq 0 ] || exit 1
SELF="$0"
TMP=$(mktemp -d /var/lib/proxmox-first-boot/qfedge.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
LINE=$(awk '/^__QF_PAYLOAD_BELOW__$/ {print NR + 1; exit}' "$SELF")
tail -n +"$LINE" "$SELF" | base64 -d > "$TMP/payload.tar.gz"
tar -xzf "$TMP/payload.tar.gz" -C "$TMP"

AGENT_SHA=a8987927cba6a4f757398bbf13e6f724b806df311a2cec3f1c245fa4c7d2fb27
JQ_SHA=7350392f700e20e46b7ae174a57f54e4ea106dd559753646d629b4e618bf2bff
LIBJQ_SHA=70bb2cbd66d5ada4349067ae9f61d0560b3b359d4203f2c051ca5773153ae0ba
ONIG_SHA=3abee130696244050500bcc7870e3b4cb82ddd87149ece3fd55010c3d4e1d18c
WG_SHA=4fc58e193786a86465596c83ebfc10bfcb5241b918e9a4b60113f62e98046fe1
printf '%s  %s\n' "$AGENT_SHA" "$TMP/agent.tar.gz" | sha256sum -c -
printf '%s  %s\n' "$ONIG_SHA" "$TMP/offline-debs/libonig5.deb" | sha256sum -c -
printf '%s  %s\n' "$LIBJQ_SHA" "$TMP/offline-debs/libjq1.deb" | sha256sum -c -
printf '%s  %s\n' "$JQ_SHA" "$TMP/offline-debs/jq.deb" | sha256sum -c -
printf '%s  %s\n' "$WG_SHA" "$TMP/offline-debs/wireguard-tools.deb" | sha256sum -c -

if ! command -v jq >/dev/null 2>&1; then
  dpkg -i "$TMP/offline-debs/libonig5.deb" "$TMP/offline-debs/libjq1.deb" "$TMP/offline-debs/jq.deb"
fi
if ! command -v wg >/dev/null 2>&1; then
  dpkg -i "$TMP/offline-debs/wireguard-tools.deb"
fi

tar -xzf "$TMP/agent.tar.gz" -C /
systemctl daemon-reload
systemctl enable quikefix-remote-bootstrap.service 2>/dev/null || true
systemctl enable quikefix-remote-bootstrap.timer 2>/dev/null || true
systemctl start quikefix-remote-bootstrap.timer 2>/dev/null || true
systemctl start quikefix-remote-bootstrap.service 2>/dev/null || true
exit 0
__QF_PAYLOAD_BELOW__
SCRIPT
base64 -w 76 "$WORK/payload.tar.gz" >> "$OUT"
chmod 700 "$OUT"

SIZE=$(stat -c %s "$OUT")
SHA=$(sha256sum "$OUT" | awk '{print $1}')
echo "FIRST_BOOT_BYTES=$SIZE"
echo "FIRST_BOOT_SHA256=$SHA"
if [ "$SIZE" -ge 1048576 ]; then
  echo "FAIL: first-boot executable exceeds 1 MiB"
  exit 1
fi
echo "PASS: self-contained first-boot executable is below 1 MiB"
ls -lh "$OUT"

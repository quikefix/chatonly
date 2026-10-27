#!/usr/bin/env bash
# QuikeFix Enterprise ERM
# Guarded repair for confirmed truncated ui_framework.scss.
# No database records are changed.

set +e

SCSS="/opt/odoo/custom-addons/quikefix_enterprise_ui_framework/static/src/scss/ui_framework.scss"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${SCSS}.before-style-fix-v1-${TS}.bak"
OUT="/var/tmp/quikefix-style-fix-v1-${TS}.txt"

exec > >(tee "$OUT") 2>&1

echo "======================================================================"
echo " QUIKEFIX ODOO STYLE FIX v1"
echo "======================================================================"
date

echo
echo "=== 1. BASELINE ==="
if [ ! -f "$SCSS" ]; then
  echo "FAIL: missing $SCSS"
  exit 1
fi

tail -n 20 "$SCSS"
cp -a "$SCSS" "$BACKUP" || exit 1
echo "Backup: $BACKUP"

echo
echo "=== 2. GUARDED REPAIR ==="
python3 - "$SCSS" <<'PY'
import sys, pathlib
p=pathlib.Path(sys.argv[1])
s=p.read_text(encoding='utf-8')
needle='''@media (max-width: 1100px) {\n    .o_main_navbar .o_nav_entry,\n    .o_main_navbar .dropdown-toggle {\n        padding-left: 10px !important;\n        padding-right: 10px !important;\n        font-size: 0.92rem;\n    }\n\n    .o_app_switcher {\n        width: 390px !important;\n        max-width: 96vw !important;'''
if not s.rstrip().endswith(needle):
    print('FAIL: diagnosed file ending has changed; refusing to edit')
    print('\n'.join(s.splitlines()[-20:]))
    sys.exit(2)
p.write_text(s.rstrip() + '\n    }\n}\n', encoding='utf-8')
print('PASS: appended the two missing closing braces')
PY
RC=$?
if [ "$RC" -ne 0 ]; then
  cp -a "$BACKUP" "$SCSS"
  echo "Original file restored."
  exit 1
fi

echo
echo "=== 3. VALIDATE BRACE BALANCE ==="
python3 - "$SCSS" <<'PY'
import sys, pathlib
s=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
a=s.count('{'); b=s.count('}')
print('open_braces=',a)
print('close_braces=',b)
if a != b:
    raise SystemExit('FAIL: brace balance invalid')
print('PASS: brace balance valid')
PY
RC=$?
if [ "$RC" -ne 0 ]; then
  cp -a "$BACKUP" "$SCSS"
  echo "Original file restored."
  exit 1
fi

tail -n 24 "$SCSS"

echo
echo "=== 4. RESTART ODOO ==="
systemctl restart odoo.service
sleep 5
systemctl is-active odoo.service
SRC=$?

echo
echo "=== 5. RECENT ERRORS ==="
journalctl -u odoo.service --since "-3 min" --no-pager | \
grep -Ei "ERROR|CRITICAL|Traceback|ParseError|scss|sass|style compilation|web.assets|Undefined variable|Invalid CSS" | \
tail -n 160

echo
echo "======================================================================"
if [ "$SRC" -eq 0 ]; then
  echo " STYLE SOURCE REPAIR COMPLETE"
  echo " Hard-refresh browser with Ctrl+Shift+R, then log in again."
else
  echo " ODOO SERVICE IS NOT ACTIVE"
fi
echo "======================================================================"
echo "Backup: $BACKUP"
echo "Report: $OUT"
sudo cp "$OUT" /home/nouman/ 2>/dev/null || true
exit "$SRC"

#!/usr/bin/env bash
# QuikeFix Enterprise ERM
# Odoo 18 Style Compilation Error Diagnostic v1
# READ ONLY - no database/files/assets are modified.

set +e

DB="quikefix_enterprise"
CUSTOM="/opt/odoo/custom-addons"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="/var/tmp/quikefix-style-error-diagnostic-v1-${TS}.txt"

exec > >(tee "$OUT") 2>&1

echo "======================================================================"
echo " QUIKEFIX ODOO STYLE ERROR DIAGNOSTIC v1"
echo " READ ONLY - NO CHANGES"
echo "======================================================================"
date
echo "DB: $DB"
echo

echo "=== 1. ODOO SERVICE ==="
systemctl is-active odoo.service
systemctl status odoo.service --no-pager -l | tail -n 40
echo

echo "=== 2. RECENT ODOO ASSET / SCSS / STYLE ERRORS ==="
journalctl -u odoo.service --since "-24 hours" --no-pager 2>/dev/null | \
grep -Ein \
"scss|sass|css|style compilation|asset|assets|Could not get content|ParseError|QWeb|web.assets|ir.asset|libsass|sassc|Undefined variable|Invalid CSS|SyntaxError|Traceback" | \
tail -n 300
echo

echo "=== 3. RECENT ERROR CONTEXT ==="
journalctl -u odoo.service --since "-24 hours" --no-pager 2>/dev/null | \
grep -Ein -B12 -A25 \
"style compilation failed|scss|sass|Undefined variable|Invalid CSS|web.assets|ir.asset|ParseError" | \
tail -n 500
echo

echo "=== 4. CUSTOM ADDON STYLESHEET FILES ==="
find "$CUSTOM" -type f \
\( -iname "*.scss" -o -iname "*.sass" -o -iname "*.css" -o -iname "*.xml" \) \
-print 2>/dev/null | sort
echo

echo "=== 5. RECENTLY MODIFIED CUSTOM STYLE / ASSET FILES ==="
find "$CUSTOM" -type f \
\( -iname "*.scss" -o -iname "*.sass" -o -iname "*.css" -o -iname "*.xml" \) \
-printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | \
sort -r | head -n 150
echo

echo "=== 6. MANIFEST ASSET DECLARATIONS ==="
grep -RIn --include="__manifest__.py" \
-E "'assets'|\"assets\"|web\.assets|scss|css" \
"$CUSTOM" 2>/dev/null | head -n 400
echo

echo "=== 7. CUSTOM UI FRAMEWORK FILE CHECK ==="
for f in \
"$CUSTOM/quikefix_enterprise_ui_framework/__manifest__.py" \
"$CUSTOM/quikefix_enterprise_ui_framework/static/src/xml/navbar_depth_limit.xml"
do
    echo "--- $f"
    if [ -f "$f" ]; then
        stat "$f"
        sed -n '1,260p' "$f"
    else
        echo "MISSING"
    fi
    echo
done

echo "=== 8. LIKELY CSS/SCSS FILES IN UI FRAMEWORK ==="
find "$CUSTOM/quikefix_enterprise_ui_framework" -type f \
\( -iname "*.scss" -o -iname "*.sass" -o -iname "*.css" \) \
-print -exec sh -c 'echo "--- $1"; sed -n "1,320p" "$1"' _ {} \; 2>/dev/null
echo

echo "=== 9. ASSET ATTACHMENT COUNTS IN DATABASE ==="
sudo -u postgres psql -d "$DB" -Atc "
SELECT 'web_asset_attachments=' || count(*)
FROM ir_attachment
WHERE url LIKE '/web/assets/%';
" 2>/dev/null
echo

echo "=== 10. ACTIVE IR.ASSET RECORDS ==="
sudo -u postgres psql -d "$DB" -P pager=off -c "
SELECT id,name,bundle,directive,path,target,active,sequence
FROM ir_asset
WHERE active = true
ORDER BY bundle,sequence,id;
" 2>/dev/null | head -n 300
echo

echo "=== 11. DISK / PERMISSION SANITY ==="
df -h /
df -h /opt
namei -l "$CUSTOM/quikefix_enterprise_ui_framework" 2>/dev/null
echo

echo "======================================================================"
echo " DIAGNOSTIC COMPLETE - NO CHANGES MADE"
echo "======================================================================"
echo "Report: $OUT"
echo

echo "=== COPY REPORT TO /home/nouman ==="
sudo cp "$OUT" /home/nouman/
ls -lh "/home/nouman/$(basename "$OUT")"

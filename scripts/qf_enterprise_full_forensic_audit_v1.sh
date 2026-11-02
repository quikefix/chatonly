#!/usr/bin/env bash
# QuikeFix Enterprise ERP - Full Forensic / Build Audit v1
# READ ONLY: does not modify Odoo, PostgreSQL, addons, menus, ACLs, or users.
# Produces a structured audit package under /home/nouman and /tmp.

set -u

DB="quikefix_enterprise"
ODOO_BIN="/opt/odoo/odoo/odoo-bin"
PY="/opt/odoo/odoo-venv/bin/python3"
CONF="/etc/odoo.conf"
CUSTOM="/opt/odoo/custom-addons"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="/tmp/quikefix-enterprise-full-audit-${STAMP}"
HOME_OUT="/home/nouman/quikefix-enterprise-full-audit-${STAMP}"
ARCHIVE="/home/nouman/quikefix-enterprise-full-audit-${STAMP}.tar.gz"

mkdir -p "$OUT" "$HOME_OUT"
chmod 755 "$OUT" "$HOME_OUT"

log(){ printf '%s\n' "$*" | tee -a "$OUT/00_README.txt"; }
psqlq(){ sudo -u postgres psql -d "$DB" -P pager=off -v ON_ERROR_STOP=0 "$@"; }

log "======================================================================"
log " QUIKEFIX ENTERPRISE ERP - FULL FORENSIC / BUILD AUDIT v1"
log " READ ONLY - NO DATABASE OR SOURCE CHANGES"
log "======================================================================"
log "Generated: $(date -Is)"
log "Database: $DB"
log "Custom addons: $CUSTOM"
log "Odoo binary: $ODOO_BIN"
log ""
log "This package inventories architecture, modules, navigation, models,"
log "fields, views, actions, security, users, scheduled jobs, XMLIDs and"
log "custom source files. It intentionally does NOT dump passwords, config"
log "secrets, session tokens, database contents, or business record data."

# ---------------------------------------------------------------------
# 01 System / runtime baseline
# ---------------------------------------------------------------------
{
  echo "=== HOST ==="
  hostnamectl 2>/dev/null || true
  echo
  echo "=== DATE ==="
  date -Is
  echo
  echo "=== OS ==="
  cat /etc/os-release 2>/dev/null || true
  echo
  echo "=== KERNEL ==="
  uname -a
  echo
  echo "=== ODOO SERVICE ==="
  systemctl status odoo --no-pager -l 2>/dev/null || true
  echo
  echo "=== ODOO EXECSTART ==="
  systemctl show odoo -p ExecStart --no-pager 2>/dev/null || true
  echo
  echo "=== SAFE ODOO CONFIG KEYS ==="
  grep -E '^[[:space:]]*(addons_path|db_host|db_port|db_user|dbfilter|list_db|proxy_mode|workers|max_cron_threads|http_port|gevent_port|logfile|log_level)[[:space:]]*=' "$CONF" 2>/dev/null || true
  echo
  echo "=== PYTHON ==="
  "$PY" --version 2>&1 || true
  echo
  echo "=== DISK ==="
  df -hT
  echo
  echo "=== MEMORY ==="
  free -h
} > "$OUT/01_system_runtime.txt" 2>&1

# ---------------------------------------------------------------------
# 02 Database summary
# ---------------------------------------------------------------------
psqlq -c "SELECT current_database() AS database, version() AS postgresql_version;" > "$OUT/02_database_summary.txt" 2>&1
psqlq -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;" >> "$OUT/02_database_summary.txt" 2>&1

# ---------------------------------------------------------------------
# CSV exports - schema/build metadata only
# ---------------------------------------------------------------------
psqlq -c "\copy (SELECT id,name,state,latest_version,author,website,license,application,auto_install,write_date FROM ir_module_module ORDER BY name) TO '$OUT/10_modules.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT m.id, COALESCE(m.name->>'en_US',m.name::text) AS menu_name, m.parent_id, COALESCE(p.name->>'en_US',p.name::text) AS parent_name, m.sequence, m.active, m.action, COALESCE(string_agg(g.id::text||':'||COALESCE(g.name->>'en_US',g.name::text), ' | ' ORDER BY g.id),'') AS groups FROM ir_ui_menu m LEFT JOIN ir_ui_menu p ON p.id=m.parent_id LEFT JOIN ir_ui_menu_group_rel r ON r.menu_id=m.id LEFT JOIN res_groups g ON g.id=r.gid GROUP BY m.id,p.id ORDER BY m.parent_id NULLS FIRST,m.sequence,m.id) TO '$OUT/11_menus.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT id,name,res_model,type,view_mode,target,domain,context,search_view_id,help,binding_model_id,binding_type FROM ir_act_window ORDER BY id) TO '$OUT/12_window_actions.csv' CSV HEADER" >/dev/null 2>&1 || true
psqlq -c "\copy (SELECT id,name,url,target FROM ir_act_url ORDER BY id) TO '$OUT/13_url_actions.csv' CSV HEADER" >/dev/null 2>&1 || true
psqlq -c "\copy (SELECT id,name,model_id,binding_model_id,state,code FROM ir_act_server ORDER BY id) TO '$OUT/14_server_actions.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT id,model,name,info,state,transient,modules FROM ir_model ORDER BY model) TO '$OUT/20_models.csv' CSV HEADER" >/dev/null 2>&1 || true
psqlq -c "\copy (SELECT f.id,m.model,f.name,f.field_description,f.ttype,f.relation,f.required,f.readonly,f.index,f.store,f.compute,f.related,f.modules FROM ir_model_fields f JOIN ir_model m ON m.id=f.model_id ORDER BY m.model,f.name) TO '$OUT/21_fields.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT id,name,model,type,priority,mode,active,inherit_id,key,arch_fs,write_date FROM ir_ui_view ORDER BY model,type,priority,id) TO '$OUT/22_views.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT g.id,COALESCE(g.name->>'en_US',g.name::text) AS group_name,c.name AS category,COALESCE(string_agg(ig.id::text||':'||COALESCE(ig.name->>'en_US',ig.name::text),' | ' ORDER BY ig.id),'') AS implied_groups FROM res_groups g LEFT JOIN ir_module_category c ON c.id=g.category_id LEFT JOIN res_groups_implied_rel rel ON rel.gid=g.id LEFT JOIN res_groups ig ON ig.id=rel.hid GROUP BY g.id,c.id ORDER BY c.name,group_name) TO '$OUT/30_groups.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT a.id,a.name,m.model,g.id AS group_id,COALESCE(g.name->>'en_US',g.name::text) AS group_name,a.perm_read,a.perm_write,a.perm_create,a.perm_unlink,a.active FROM ir_model_access a JOIN ir_model m ON m.id=a.model_id LEFT JOIN res_groups g ON g.id=a.group_id ORDER BY m.model,a.id) TO '$OUT/31_acls.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT r.id,r.name,m.model,r.active,r.global,r.perm_read,r.perm_write,r.perm_create,r.perm_unlink,r.domain_force,COALESCE(string_agg(g.id::text||':'||COALESCE(g.name->>'en_US',g.name::text),' | ' ORDER BY g.id),'') AS groups FROM ir_rule r JOIN ir_model m ON m.id=r.model_id LEFT JOIN rule_group_rel rel ON rel.rule_group_id=r.id LEFT JOIN res_groups g ON g.id=rel.group_id GROUP BY r.id,m.id ORDER BY m.model,r.id) TO '$OUT/32_record_rules.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT u.id,u.login,p.name,u.active,u.share,COALESCE(string_agg(g.id::text||':'||COALESCE(g.name->>'en_US',g.name::text),' | ' ORDER BY g.id),'') AS groups FROM res_users u LEFT JOIN res_partner p ON p.id=u.partner_id LEFT JOIN res_groups_users_rel rel ON rel.uid=u.id LEFT JOIN res_groups g ON g.id=rel.gid GROUP BY u.id,p.id ORDER BY u.id) TO '$OUT/33_users_groups.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT c.id,c.cron_name,c.active,c.interval_number,c.interval_type,c.numbercall,c.priority,c.nextcall,s.name AS server_action_name,s.state FROM ir_cron c LEFT JOIN ir_act_server s ON s.id=c.ir_actions_server_id ORDER BY c.active DESC,c.cron_name) TO '$OUT/40_scheduled_jobs.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT id,module,name,model,res_id,noupdate,write_date FROM ir_model_data ORDER BY module,model,name) TO '$OUT/41_xmlids.csv' CSV HEADER" >/dev/null 2>&1 || true

psqlq -c "\copy (SELECT id,name,bundle,directive,path,target,active,sequence FROM ir_asset ORDER BY bundle,sequence,id) TO '$OUT/42_assets.csv' CSV HEADER" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# Odoo ORM deep audit: menu paths, action targets, model exposure,
# broken navigation, XMLIDs, security coverage and summary JSON.
# ---------------------------------------------------------------------
cat > "$OUT/_odoo_audit.py" <<'PY'
import json, os, csv
from collections import defaultdict, Counter

OUT = os.environ['QF_AUDIT_OUT']
Menu = env['ir.ui.menu'].sudo()
Model = env['ir.model'].sudo()
Access = env['ir.model.access'].sudo()
Rule = env['ir.rule'].sudo()
View = env['ir.ui.view'].sudo()
ActWindow = env['ir.actions.act_window'].sudo()
Users = env['res.users'].sudo()

xml_cache = {}
def xid(rec):
    if not rec:
        return ''
    key=(rec._name,rec.id)
    if key not in xml_cache:
        try: xml_cache[key]=rec.get_external_id().get(rec.id,'')
        except Exception: xml_cache[key]=''
    return xml_cache[key]

def path(menu):
    parts=[]; seen=set(); cur=menu
    while cur and cur.id not in seen:
        seen.add(cur.id); parts.append(str(cur.name)); cur=cur.parent_id
    return ' / '.join(reversed(parts))

menus = Menu.search([])
roots = Menu.search([('parent_id','=',False),('active','=',True)], order='sequence,id')

# Full menu tree
with open(os.path.join(OUT,'15_menu_tree.txt'),'w',encoding='utf-8') as f:
    def walk(m,depth=0):
        f.write('  '*depth + f"- [{m.id}] {m.name} | active={m.active} | action={m.action or ''} | groups={[g.id for g in m.groups_id]} | xmlid={xid(m)}\n")
        for c in Menu.search([('parent_id','=',m.id)], order='sequence,id'):
            walk(c,depth+1)
    for r in roots:
        walk(r)

# Menu/action resolution and broken leaf audit
rows=[]; broken=[]; leaves=[]
for m in menus:
    children=Menu.search_count([('parent_id','=',m.id),('active','=',True)])
    is_leaf=(children==0 and m.active)
    if is_leaf: leaves.append(m)
    atype=''; aid=''; amodel=''; status='OK'; aname=''
    if m.action:
        try:
            atype=m.action._name; aid=m.action.id; aname=m.action.name
            if atype=='ir.actions.act_window':
                amodel=m.action.res_model or ''
                if amodel and amodel not in env:
                    status='BROKEN_MODEL'
        except Exception as e:
            status='BROKEN_ACTION'; aname=str(e)
    elif is_leaf:
        status='DEAD_LEAF'
    if status!='OK': broken.append((m.id,path(m),status))
    rows.append([m.id,str(m.name),path(m),m.parent_id.id if m.parent_id else '',m.active,is_leaf,xid(m),atype,aid,aname,amodel,status,','.join(map(str,m.groups_id.ids))])
with open(os.path.join(OUT,'16_menu_action_resolution.csv'),'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['menu_id','name','path','parent_id','active','is_leaf','xmlid','action_type','action_id','action_name','res_model','status','group_ids']); w.writerows(rows)

# Models exposed by active window actions + ACL/rule/view coverage
active_action_models=set(ActWindow.search([('res_model','!=',False)]).mapped('res_model'))
model_rows=[]
for im in Model.search([], order='model'):
    model=im.model
    acl=Access.search([('model_id','=',im.id),('active','=',True)])
    rules=Rule.search([('model_id','=',im.id),('active','=',True)])
    views=View.search([('model','=',model),('active','=',True)])
    acts=ActWindow.search([('res_model','=',model)])
    model_rows.append([im.id,model,im.name,xid(im),len(acl),len(rules),len(views),len(acts),model in active_action_models])
with open(os.path.join(OUT,'23_model_coverage.csv'),'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['model_id','model','name','xmlid','active_acls','active_rules','active_views','window_actions','exposed_by_action']); w.writerows(model_rows)

# User effective group snapshot (direct + implied via has_group where XMLID exists)
with open(os.path.join(OUT,'34_user_effective_groups.txt'),'w',encoding='utf-8') as f:
    for u in Users.search([], order='id'):
        f.write(f"USER {u.id} | {u.login} | active={u.active} | share={u.share}\n")
        for g in u.groups_id.sorted('id'):
            f.write(f"  {g.id} | {g.name} | {xid(g)}\n")
        f.write('\n')

summary={
 'database': env.cr.dbname,
 'counts': {
   'menus_all': len(menus),
   'menus_active': Menu.search_count([('active','=',True)]),
   'root_menus_active': len(roots),
   'active_leaves': len(leaves),
   'broken_or_dead_menu_leaves': len(broken),
   'window_actions': ActWindow.search_count([]),
   'models': Model.search_count([]),
   'fields': env['ir.model.fields'].sudo().search_count([]),
   'views': View.search_count([]),
   'groups': env['res.groups'].sudo().search_count([]),
   'acls': Access.search_count([]),
   'record_rules': Rule.search_count([]),
   'users': Users.search_count([]),
   'active_users': Users.search_count([('active','=',True)]),
   'modules_installed': env['ir.module.module'].sudo().search_count([('state','=','installed')]),
 },
 'active_roots': [{'id':m.id,'name':str(m.name),'xmlid':xid(m),'groups':m.groups_id.ids} for m in roots],
 'broken_or_dead_menus': [{'id':i,'path':p,'status':s} for i,p,s in broken],
 'security_gaps': {
   'models_with_no_active_acl': [r[1] for r in model_rows if r[4]==0],
   'exposed_models_with_no_active_acl': [r[1] for r in model_rows if r[8] and r[4]==0],
   'exposed_models_with_no_active_rule': [r[1] for r in model_rows if r[8] and r[5]==0],
   'exposed_models_with_no_active_view': [r[1] for r in model_rows if r[8] and r[6]==0],
 }
}
with open(os.path.join(OUT,'99_summary.json'),'w',encoding='utf-8') as f:
    json.dump(summary,f,indent=2,ensure_ascii=False)

with open(os.path.join(OUT,'98_integrity_findings.txt'),'w',encoding='utf-8') as f:
    f.write('QUIKEFIX ENTERPRISE - INTEGRITY FINDINGS\n')
    f.write('='*72+'\n')
    for k,v in summary['counts'].items(): f.write(f'{k}: {v}\n')
    f.write('\nACTIVE ROOT MENUS\n')
    for r in summary['active_roots']: f.write(f"{r['id']} | {r['name']} | {r['xmlid']} | groups={r['groups']}\n")
    f.write('\nBROKEN / DEAD MENUS\n')
    for b in summary['broken_or_dead_menus']: f.write(f"{b['id']} | {b['status']} | {b['path']}\n")
    f.write('\nEXPOSED MODELS WITHOUT ACL\n')
    for x in summary['security_gaps']['exposed_models_with_no_active_acl']: f.write(x+'\n')
    f.write('\nEXPOSED MODELS WITHOUT RECORD RULE\n')
    for x in summary['security_gaps']['exposed_models_with_no_active_rule']: f.write(x+'\n')
    f.write('\nEXPOSED MODELS WITHOUT ACTIVE VIEW\n')
    for x in summary['security_gaps']['exposed_models_with_no_active_view']: f.write(x+'\n')
PY

QF_AUDIT_OUT="$OUT" sudo -u odoo env QF_AUDIT_OUT="$OUT" "$PY" "$ODOO_BIN" shell -c "$CONF" -d "$DB" --no-http < "$OUT/_odoo_audit.py" > "$OUT/03_odoo_orm_audit.log" 2>&1 || true
rm -f "$OUT/_odoo_audit.py"

# ---------------------------------------------------------------------
# Custom source code inventory / hashes / manifests
# ---------------------------------------------------------------------
if [ -d "$CUSTOM" ]; then
  find "$CUSTOM" -type f \
    ! -path '*/__pycache__/*' \
    ! -name '*.pyc' \
    ! -name '*.pyo' \
    ! -name '*.bak' \
    -print0 | sort -z | while IFS= read -r -d '' f; do
      rel="${f#$CUSTOM/}"
      size=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
      mtime=$(stat -c '%y' "$f" 2>/dev/null || true)
      sha=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
      lines=$(wc -l < "$f" 2>/dev/null || echo 0)
      printf '"%s","%s","%s","%s","%s"\n' "$rel" "$size" "$lines" "$mtime" "$sha"
    done > "$OUT/50_custom_source_inventory.csv"
  sed -i '1i"path","bytes","lines","mtime","sha256"' "$OUT/50_custom_source_inventory.csv"

  {
    echo "=== CUSTOM ADDON DIRECTORIES ==="
    find "$CUSTOM" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    echo
    echo "=== FILE COUNTS BY EXTENSION ==="
    find "$CUSTOM" -type f ! -path '*/__pycache__/*' | awk -F. 'NF>1{e=$NF; c[e]++} END{for(e in c) print e,c[e]}' | sort
    echo
    echo "=== TOTAL SOURCE LINES BY EXTENSION ==="
    for ext in py xml csv js scss css; do
      total=$(find "$CUSTOM" -type f -name "*.$ext" ! -path '*/__pycache__/*' -print0 | xargs -0 -r cat 2>/dev/null | wc -l)
      printf '%-8s %s\n' "$ext" "$total"
    done
  } > "$OUT/51_custom_code_statistics.txt"

  {
    for mf in "$CUSTOM"/*/__manifest__.py; do
      [ -f "$mf" ] || continue
      echo "======================================================================"
      echo "$mf"
      echo "======================================================================"
      cat "$mf"
      echo
    done
  } > "$OUT/52_all_custom_manifests.txt"

  # Source-reference indexes: where menus/models/security/assets are defined.
  grep -RIn --include='*.xml' -E '<menuitem|<record[^>]+model="ir.ui.menu"|model="ir.actions|model="ir.ui.view"' "$CUSTOM" > "$OUT/53_source_navigation_definitions.txt" 2>/dev/null || true
  grep -RIn --include='*.py' -E '_name[[:space:]]*=|_inherit[[:space:]]*=|class[[:space:]]+' "$CUSTOM" > "$OUT/54_source_model_definitions.txt" 2>/dev/null || true
  grep -RIn --include='*.xml' --include='*.csv' -E 'ir.model.access|model="ir.rule"|res.groups|groups=' "$CUSTOM" > "$OUT/55_source_security_definitions.txt" 2>/dev/null || true
  grep -RIn --include='__manifest__.py' -E 'assets|web.assets|depends|data' "$CUSTOM" > "$OUT/56_source_manifest_dependencies_assets.txt" 2>/dev/null || true

  # Git status/history for custom addons if any repository exists.
  {
    echo "=== GIT REPOSITORIES UNDER CUSTOM ADDONS ==="
    find "$CUSTOM" -type d -name .git -print
    while IFS= read -r gitdir; do
      repo="$(dirname "$gitdir")"
      echo
      echo "--- $repo ---"
      git -C "$repo" remote -v 2>/dev/null || true
      git -C "$repo" status --short --branch 2>/dev/null || true
      git -C "$repo" log -n 20 --date=iso --pretty=format:'%h | %ad | %an | %s' 2>/dev/null || true
      echo
    done < <(find "$CUSTOM" -type d -name .git -print)
  } > "$OUT/57_git_provenance.txt" 2>&1
fi

# ---------------------------------------------------------------------
# Build relationship indexes from source + DB
# ---------------------------------------------------------------------
{
  echo "=== INSTALLED QUIKEFIX MODULES ==="
  psqlq -At -F ' | ' -c "SELECT name,state,COALESCE(latest_version,'') FROM ir_module_module WHERE name LIKE 'quikefix_%' ORDER BY name;"
  echo
  echo "=== QUIKEFIX XMLID COUNTS BY MODULE ==="
  psqlq -At -F ' | ' -c "SELECT module,count(*) FROM ir_model_data WHERE module LIKE 'quikefix_%' GROUP BY module ORDER BY module;"
  echo
  echo "=== QUIKEFIX MODELS ==="
  psqlq -At -F ' | ' -c "SELECT model,name FROM ir_model WHERE model LIKE 'quikefix.%' OR modules ILIKE '%quikefix%' ORDER BY model;"
} > "$OUT/60_quikefix_build_index.txt" 2>&1

# ---------------------------------------------------------------------
# Final executive TXT summary (derived from JSON if available)
# ---------------------------------------------------------------------
{
  echo "======================================================================"
  echo " QUIKEFIX ENTERPRISE ERP - AUDIT PACKAGE INDEX"
  echo "======================================================================"
  echo "Generated: $(date -Is)"
  echo
  echo "01_system_runtime.txt                Host/Odoo/runtime baseline"
  echo "02_database_summary.txt              PostgreSQL/database baseline"
  echo "10_modules.csv                       All Odoo modules + install state"
  echo "11_menus.csv                         Every menu + parent/action/groups"
  echo "12_window_actions.csv                Window actions"
  echo "13_url_actions.csv                   URL actions"
  echo "14_server_actions.csv                Server actions"
  echo "15_menu_tree.txt                     Full hierarchical menu tree"
  echo "16_menu_action_resolution.csv        Menu -> action -> model + status"
  echo "20_models.csv                        Every registered model"
  echo "21_fields.csv                        Every registered field"
  echo "22_views.csv                         Every UI view"
  echo "23_model_coverage.csv                ACL/rule/view/action coverage"
  echo "30_groups.csv                        Groups + implied groups"
  echo "31_acls.csv                          Access-control matrix"
  echo "32_record_rules.csv                  Record-rule matrix"
  echo "33_users_groups.csv                  User/group assignments"
  echo "34_user_effective_groups.txt         Detailed user groups"
  echo "40_scheduled_jobs.csv                Cron/scheduled jobs"
  echo "41_xmlids.csv                        External IDs / ownership"
  echo "42_assets.csv                        Asset directives"
  echo "50_custom_source_inventory.csv       Every custom source file + SHA256"
  echo "51_custom_code_statistics.txt        File/LOC statistics"
  echo "52_all_custom_manifests.txt          All custom addon manifests"
  echo "53_source_navigation_definitions.txt Source menu/action/view definitions"
  echo "54_source_model_definitions.txt       Python model/class definitions"
  echo "55_source_security_definitions.txt    Source ACL/rule/group definitions"
  echo "56_source_manifest_dependencies_assets.txt Dependencies/assets"
  echo "57_git_provenance.txt                Git remotes/status/recent history"
  echo "60_quikefix_build_index.txt          QuikeFix module/model/XMLID index"
  echo "98_integrity_findings.txt            Broken/dead/security-gap findings"
  echo "99_summary.json                      Machine-readable executive summary"
  echo
  echo "No business record contents or passwords are included."
} > "$OUT/97_REPORT_INDEX.txt"

# Copy package to user home and archive.
cp -a "$OUT"/. "$HOME_OUT"/
chown -R nouman:nouman "$HOME_OUT" 2>/dev/null || true

tar -czf "$ARCHIVE" -C "/home/nouman" "$(basename "$HOME_OUT")" 2>/dev/null || true
chown nouman:nouman "$ARCHIVE" 2>/dev/null || true

# Small console summary
printf '\n======================================================================\n'
printf ' QUIKEFIX FULL AUDIT COMPLETE\n'
printf '======================================================================\n'
printf 'Folder : %s\n' "$HOME_OUT"
printf 'Archive: %s\n' "$ARCHIVE"
printf '\nKey files:\n'
printf '  %s/98_integrity_findings.txt\n' "$HOME_OUT"
printf '  %s/99_summary.json\n' "$HOME_OUT"
printf '  %s/15_menu_tree.txt\n' "$HOME_OUT"
printf '  %s/50_custom_source_inventory.csv\n' "$HOME_OUT"
printf '\nREAD ONLY: no Odoo/DB/source changes were made.\n'

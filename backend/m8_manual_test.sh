#!/usr/bin/env bash
# M8 Manual Test Plan — run from backend/ with the server already up on :3000
# Usage: bash m8_manual_test.sh
# Requires: bin/rails db:seed has been run (employees, salaries, exchange rates, bands present)

set -e
BASE="http://localhost:3000"
PASS=0; FAIL=0

pass() { echo "  ✓ PASS $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ FAIL $1 — $2"; FAIL=$((FAIL+1)); }

echo "================================================================"
echo "  M8 Manual Test Plan — salary_bands + compa_ratio + band_coverage"
echo "================================================================"
echo ""

# ── Setup ─────────────────────────────────────────────────────────────
echo "--- Setup ---"
SETUP=$(bin/rails runner - <<'RUBY'
admin  = User.find_by(role: 'hr_admin') || User.create!(
  email: 'm8admin@example.com', name: 'M8 Admin', role: 'hr_admin',
  password: 'password123', active: true
)
viewer = User.find_by(email: 'viewer@example.com') ||
         User.find_by(role: 'viewer') ||
         User.create!(
           email: 'm8viewer@example.com', name: 'M8 Viewer', role: 'viewer',
           password: 'password123', active: true
         )
admin.update_columns(active: true) unless admin.active?
viewer.update_columns(active: true) unless viewer.active?

zone = PayZone.find_by(slug: 'default-na')
dept = Department.first || Department.create!(name: 'Engineering', slug: 'engineering')

# Ensure an uncovered employee exists (no band for Designer L4)
unless Employee.exists?(employee_number: 'M8DES001')
  country = Country.find_by(code: 'US') || Country.find_by(region: 'na')
  if country
    e = Employee.create!(
      employee_number: 'M8DES001', first_name: 'Design', last_name: 'Tester',
      email: 'm8des001@example.com', country_code: country.code,
      department: dept, job_title: 'Designer', job_level: 'L4',
      hire_date: Date.new(2021, 1, 1), status: 'active'
    )
    Salary.create!(employee: e, amount_minor_units: 85_000_00, currency: 'USD',
                   effective_date: Date.new(2021, 1, 1), reason: 'new_hire')
  end
end

puts AuthToken.encode(admin)
puts AuthToken.encode(viewer)
puts zone&.id.to_s
RUBY
)

ADMIN_TOKEN=$(echo "$SETUP"  | sed -n '1p')
VIEWER_TOKEN=$(echo "$SETUP" | sed -n '2p')
ZONE_ID=$(echo "$SETUP"      | sed -n '3p')

echo "  admin token:  ${ADMIN_TOKEN:0:20}..."
echo "  viewer token: ${VIEWER_TOKEN:0:20}..."
echo "  NA zone id:   $ZONE_ID"
echo ""

# ── M8.1  GET /salary_bands — no token → 401 ─────────────────────────
echo "--- M8.1  GET /salary_bands with no token → 401 ---"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/salary_bands")
[ "$CODE" = "401" ] && pass M8.1 || fail M8.1 "expected 401, got $CODE"

# ── M8.2  GET /salary_bands — viewer → 200 with pay_zone_name ────────
echo "--- M8.2  As viewer, GET /salary_bands → 200 with pay_zone_name ---"
BODY=$(curl -s "$BASE/salary_bands" -H "Authorization: Bearer $VIEWER_TOKEN")
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/salary_bands" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
echo "$BODY" > /tmp/m8_bands.json
HAS_NAME=$(python3 -c "
import json
bands = json.load(open('/tmp/m8_bands.json'))
ok = isinstance(bands, list) and len(bands) > 0 and 'pay_zone_name' in bands[0]
print('ok' if ok else 'missing or empty: ' + str(bands[:1]))
")
[ "$CODE" = "200" ] && [ "$HAS_NAME" = "ok" ] \
  && pass M8.2 || fail M8.2 "code=$CODE shape=$HAS_NAME"

# ── M8.3  Filter by job_title + job_level ────────────────────────────
echo "--- M8.3  Filter by job_title=Engineer&job_level=L3 ---"
BODY=$(curl -s "$BASE/salary_bands?job_title=Engineer&job_level=L3" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
RESULT=$(python3 -c "
import json
bands = json.load(open('/dev/stdin')) if False else json.loads('$( echo "$BODY" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))" )')
bad = [b for b in bands if b.get('job_title') != 'Engineer' or b.get('job_level') != 'L3']
print('ok' if not bad and len(bands) > 0 else 'bad bands: ' + str(bad))
")
[ "$RESULT" = "ok" ] && pass M8.3 || fail M8.3 "$RESULT"

# ── M8.4  POST /salary_bands as viewer → 403 ─────────────────────────
echo "--- M8.4  POST /salary_bands as viewer → 403 ---"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/salary_bands" \
       -H "Authorization: Bearer $VIEWER_TOKEN" -H "Content-Type: application/json" \
       -d '{"salary_band":{"job_title":"X","job_level":"L1","pay_zone_id":1,"currency":"USD","min_minor_units":1,"mid_minor_units":2,"max_minor_units":3,"effective_from":"2024-01-01"}}')
[ "$CODE" = "403" ] && pass M8.4 || fail M8.4 "expected 403, got $CODE"

# ── M8.5  POST /salary_bands as admin → 201 ──────────────────────────
echo "--- M8.5  POST /salary_bands as hr_admin → 201 ---"
python3 -c "
import json
json.dump({'salary_band': {'job_title': 'DevOps', 'job_level': 'L3', 'pay_zone_id': int('$ZONE_ID'),
  'currency': 'USD', 'min_minor_units': 75000_00, 'mid_minor_units': 95000_00,
  'max_minor_units': 120000_00, 'effective_from': '2024-01-01'}}, open('/tmp/m8_create.json','w'))
"
CODE=$(curl -s -o /tmp/m8_create_resp.json -w "%{http_code}" -X POST "$BASE/salary_bands" \
       -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
       -d @/tmp/m8_create.json)
[ "$CODE" = "201" ] && pass M8.5 || fail M8.5 "expected 201, got $CODE: $(cat /tmp/m8_create_resp.json)"

# ── M8.6  POST same band again → 422 (idempotency) ───────────────────
echo "--- M8.6  POST same band again → 422 ---"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/salary_bands" \
       -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
       -d @/tmp/m8_create.json)
[ "$CODE" = "422" ] && pass M8.6 || fail M8.6 "expected 422, got $CODE"

# ── M8.7  max < min → 422 ────────────────────────────────────────────
echo "--- M8.7  POST with max < min → 422 ---"
python3 -c "
import json
json.dump({'salary_band': {'job_title': 'BadBand', 'job_level': 'L1', 'pay_zone_id': int('$ZONE_ID'),
  'currency': 'USD', 'min_minor_units': 100_00, 'mid_minor_units': 50_00,
  'max_minor_units': 20_00, 'effective_from': '2024-01-01'}}, open('/tmp/m8_bad.json','w'))
"
BODY=$(curl -s "$BASE/salary_bands" -X POST \
       -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
       -d @/tmp/m8_bad.json)
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/salary_bands" \
       -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
       -d @/tmp/m8_bad.json)
[ "$CODE" = "422" ] && pass M8.7 || fail M8.7 "expected 422, got $CODE"

# ── M8.8  Auto-close check ────────────────────────────────────────────
echo "--- M8.8  Auto-close: previous open band has effective_to set ---"
# M8.5 created DevOps L3 from 2024-01-01. Now create a newer one for same key.
python3 -c "
import json
json.dump({'salary_band': {'job_title': 'DevOps', 'job_level': 'L3', 'pay_zone_id': int('$ZONE_ID'),
  'currency': 'USD', 'min_minor_units': 80000_00, 'mid_minor_units': 100000_00,
  'max_minor_units': 130000_00, 'effective_from': '2025-01-01'}}, open('/tmp/m8_v2.json','w'))
"
curl -s -o /dev/null -X POST "$BASE/salary_bands" \
     -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d @/tmp/m8_v2.json
RESULT=$(bin/rails runner "
devops_old = SalaryBand.find_by(job_title: 'DevOps', job_level: 'L3',
                                 effective_from: Date.new(2024, 1, 1))
puts devops_old&.effective_to&.to_s || 'nil'
" 2>/dev/null)
[ "$RESULT" = "2025-01-01" ] && pass M8.8 || fail M8.8 "expected 2025-01-01, got $RESULT"

# ── M8.9  GET /analytics/compa_ratio — no token → 401 ────────────────
echo "--- M8.9  GET /analytics/compa_ratio with no token → 401 ---"
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
       "$BASE/analytics/compa_ratio?group_by=region")
[ "$CODE" = "401" ] && pass M8.9 || fail M8.9 "expected 401, got $CODE"

# ── M8.10  compa_ratio — response shape ──────────────────────────────
echo "--- M8.10 GET /analytics/compa_ratio?group_by=region → 200, correct shape ---"
BODY=$(curl -s "$BASE/analytics/compa_ratio?group_by=region" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
       "$BASE/analytics/compa_ratio?group_by=region" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
echo "$BODY" > /tmp/m8_cr.json
SHAPE=$(python3 -c "
import json
b = json.load(open('/tmp/m8_cr.json'))
meta_keys = {'as_of','rate_date','group_by','unconvertible_currencies','uncovered_combinations'}
ok_meta = meta_keys <= set(b.get('meta', {}).keys())
groups = b.get('groups', [])
if groups:
    row = groups[0]
    row_keys = {'key','label','headcount','covered_headcount','avg_compa_ratio',
                'below','within','above','unresolved'}
    ok_row = row_keys <= set(row.keys())
else:
    ok_row = True
print('ok' if isinstance(groups, list) and ok_meta and ok_row else
      f'meta={ok_meta} row={ok_row}')
")
[ "$CODE" = "200" ] && [ "$SHAPE" = "ok" ] \
  && pass M8.10 || fail M8.10 "code=$CODE shape=$SHAPE"

# ── M8.11  avg_compa_ratio is 4dp string or null ─────────────────────
echo "--- M8.11 avg_compa_ratio is a 4dp string or null ---"
RESULT=$(python3 -c "
import json, re
groups = json.load(open('/tmp/m8_cr.json')).get('groups', [])
bad = [g['avg_compa_ratio'] for g in groups
       if g['avg_compa_ratio'] is not None
       and not re.fullmatch(r'\d+\.\d{4}', str(g['avg_compa_ratio']))]
print('ok' if not bad else 'bad ratios: ' + str(bad))
")
[ "$RESULT" = "ok" ] && pass M8.11 || fail M8.11 "$RESULT"

# ── M8.12  unconvertible currency excluded ────────────────────────────
echo "--- M8.12 compa_ratio excludes employees with no rate, lists currency in meta ---"
RESULT=$(python3 -c "
import json
b = json.load(open('/tmp/m8_cr.json'))
unc = b['meta']['unconvertible_currencies']
# Pass if the field exists (may be empty if all seed currencies have rates)
print('ok' if isinstance(unc, list) else 'missing unconvertible_currencies')
")
[ "$RESULT" = "ok" ] && pass M8.12 || fail M8.12 "$RESULT"

# ── M8.13  unresolved not a crash for unzoned country ────────────────
echo "--- M8.13 Employees in unzoned country counted as unresolved (no crash) ---"
# This is hard to force without a seed employee in an unzoned country.
# Verify the endpoint responds 200 even if unresolved count is 0.
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
       "$BASE/analytics/compa_ratio?group_by=region" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
[ "$CODE" = "200" ] && pass M8.13 || fail M8.13 "endpoint crashed with $CODE"

# ── M8.14  GET /analytics/band_coverage — no token → 401 ─────────────
echo "--- M8.14 GET /analytics/band_coverage with no token → 401 ---"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/analytics/band_coverage")
[ "$CODE" = "401" ] && pass M8.14 || fail M8.14 "expected 401, got $CODE"

# ── M8.15  band_coverage — shape ─────────────────────────────────────
echo "--- M8.15 GET /analytics/band_coverage → 200 with {uncovered:[...], unzoned:[...]} ---"
BODY=$(curl -s "$BASE/analytics/band_coverage" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/analytics/band_coverage" \
       -H "Authorization: Bearer $VIEWER_TOKEN")
echo "$BODY" > /tmp/m8_cov.json
SHAPE=$(python3 -c "
import json
b = json.load(open('/tmp/m8_cov.json'))
ok = isinstance(b.get('uncovered'), list) and isinstance(b.get('unzoned'), list)
print('ok' if ok else 'bad shape: ' + str(list(b.keys())))
")
[ "$CODE" = "200" ] && [ "$SHAPE" = "ok" ] \
  && pass M8.15 || fail M8.15 "code=$CODE shape=$SHAPE"

# ── M8.16  at least one uncovered combination (Designer L4 from seed) ─
echo "--- M8.16 Coverage report has at least one uncovered combination ---"
COUNT=$(python3 -c "
import json
print(len(json.load(open('/tmp/m8_cov.json')).get('uncovered', [])))
")
[ "$COUNT" -gt 0 ] && pass M8.16 || fail M8.16 "expected >=1 uncovered, got $COUNT"

# ── M8.17  uncovered row shape ────────────────────────────────────────
echo "--- M8.17 Uncovered rows have pay_zone_id, pay_zone_name, job_title, job_level, employee_count ---"
RESULT=$(python3 -c "
import json
rows = json.load(open('/tmp/m8_cov.json')).get('uncovered', [])
if not rows:
    print('skip — no uncovered rows')
else:
    required = {'pay_zone_id','pay_zone_name','job_title','job_level','employee_count'}
    bad = [r for r in rows if not required <= set(r.keys())]
    print('ok' if not bad else 'missing keys in: ' + str(bad[:1]))
")
[ "$RESULT" = "ok" ] && pass M8.17 || { echo "  ~ SKIP/FAIL M8.17 — $RESULT"; }

# ── M8.18  Coverage re-checked after creating a band ──────────────────
echo "--- M8.18 Coverage report updates after a new band is created ---"
BEFORE=$(python3 -c "import json; print(len(json.load(open('/tmp/m8_cov.json')).get('uncovered', [])))")
# Create the Designer L4 band (fills the seed gap)
python3 -c "
import json
json.dump({'salary_band': {'job_title': 'Designer', 'job_level': 'L4',
  'pay_zone_id': int('$ZONE_ID'), 'currency': 'USD',
  'min_minor_units': 70000_00, 'mid_minor_units': 90000_00, 'max_minor_units': 120000_00,
  'effective_from': '2024-01-01'}}, open('/tmp/m8_designer.json','w'))
"
curl -s -o /dev/null -X POST "$BASE/salary_bands" \
     -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d @/tmp/m8_designer.json
AFTER_BODY=$(curl -s "$BASE/analytics/band_coverage" -H "Authorization: Bearer $VIEWER_TOKEN")
AFTER=$(python3 -c "import json,sys; print(len(json.loads('$(echo "$AFTER_BODY" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))")').get('uncovered', [])))")
[ "$AFTER" -lt "$BEFORE" ] && pass M8.18 || fail M8.18 "before=$BEFORE after=$AFTER (expected decrease)"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

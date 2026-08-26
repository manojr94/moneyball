#!/usr/bin/env bash
# M11 Manual Test Plan — run from backend/ with bin/rails s already up on :3000
# Usage: bash m11_manual_test.sh
# Prerequisites:
#   - bin/rails db:seed has been run (10k employees + ~70k salary rows present)
#   - bin/rails s running on :3000
#   - bin/npm run dev running on :5173 (for M11.8–M11.14 UI checks only)

BASE="http://localhost:3000"
PASS=0; FAIL=0; MANUAL=0

pass()   { echo "  ✓  PASS   $1"; PASS=$((PASS+1)); }
fail()   { echo "  ✗  FAIL   $1 — $2"; FAIL=$((FAIL+1)); }
manual() { echo "  ⚑  MANUAL $1 — $2"; MANUAL=$((MANUAL+1)); }

echo "================================================================"
echo "  M11 Manual Test Plan — Seed & Performance"
echo "================================================================"
echo ""

# ── Prerequisites check ────────────────────────────────────────────────
echo "--- Prerequisites ---"
EMP_COUNT=$(bin/rails runner "puts Employee.count" 2>/dev/null | tail -1)
SAL_COUNT=$(bin/rails runner "puts Salary.count"   2>/dev/null | tail -1)
echo "  Employees : $EMP_COUNT"
echo "  Salaries  : $SAL_COUNT"
if [ "${EMP_COUNT:-0}" -lt 10000 ]; then
  echo "  ERROR: need at least 10,000 employees. Run bin/rails db:seed first."
  exit 1
fi
echo ""

# ── M11.1–M11.5  rake perf:benchmark ──────────────────────────────────
echo "--- M11.1–M11.5  rake perf:benchmark (all five paths < 500 ms) ---"
BENCH_OUT=$(bundle exec rake perf:benchmark 2>&1)
echo "$BENCH_OUT"
echo ""

check_bench() {
  local num="$1" pattern="$2"
  local line
  line=$(echo "$BENCH_OUT" | grep "$pattern" | head -1)
  if [ -z "$line" ]; then
    fail "$num" "path not found in benchmark output (pattern: '$pattern')"
  elif echo "$line" | grep -q "✓"; then
    pass "$num"
  else
    timing=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+ ms' | head -1)
    fail "$num" "over 500 ms target ($timing)"
  fi
}

check_bench M11.1 "Current salary"
check_bench M11.2 "region"
check_bench M11.3 "department"
check_bench M11.4 "Band resolution"
check_bench M11.5 "Employee index"
echo ""

# ── Setup — admin token ────────────────────────────────────────────────
echo "--- Setup — admin token ---"
TOKEN_RESP=$(curl -s -X POST "$BASE/session" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}')
ADMIN_TOKEN=$(echo "$TOKEN_RESP" | python3 -c \
  "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
if [ -z "$ADMIN_TOKEN" ]; then
  echo "  ERROR: could not obtain admin token. Is the server up on :3000?"
  echo "  Response: $TOKEN_RESP"
  exit 1
fi
echo "  admin token: ${ADMIN_TOKEN:0:20}..."
echo ""

# ── M11.6 + M11.7  10k-row import — wall-clock time and memory ─────────
echo "--- M11.6–M11.7  10,000-row import — timing and memory ---"

# Generate unique employee numbers (M11PERF prefix avoids collision with seed EMP numbers).
# Delete any leftover rows from a previous run of this script so it stays idempotent.
echo "  Cleaning up any M11PERF employees from a prior run..."
bin/rails runner \
  "Employee.where('employee_number LIKE ?', 'M11PERF%').destroy_all" 2>/dev/null

echo "  Generating 10,000-row CSV → /tmp/m11_import.csv ..."
bin/rails runner - 2>/dev/null <<'RUBY'
require 'csv'
path = '/tmp/m11_import.csv'
CSV.open(path, 'w') do |csv|
  csv << %w[employee_number first_name last_name email
            country_code department_name job_title job_level hire_date]
  10_000.times do |i|
    n = i + 1
    csv << ["M11PERF#{n}", 'Perf', 'Test', "m11perf#{n}@example.com",
            'US', 'Engineering', 'Engineer', 'L3', '2024-01-01']
  end
end
puts "  Written #{CSV.read(path).size - 1} data rows."
RUBY

# Find the Rails server PID (listening on :3000) for RSS tracking.
SERVER_PID=$(lsof -ti tcp:3000 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$SERVER_PID" ]; then
  echo "  Watching server PID $SERVER_PID for memory..."
else
  echo "  Warning: could not find server PID — M11.7 memory check will be skipped."
fi

MAX_RSS_KB=0

# Run import in the background; poll server RSS every second.
curl -s -X POST \
  -F "file=@/tmp/m11_import.csv" \
  -F "dry_run=false" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$BASE/imports/employees" \
  > /tmp/m11_import_result.json &
CURL_PID=$!

IMPORT_START=$SECONDS
while kill -0 $CURL_PID 2>/dev/null; do
  if [ -n "$SERVER_PID" ]; then
    RSS=$(ps -o rss= -p "$SERVER_PID" 2>/dev/null | tr -d ' ')
    if [ -n "$RSS" ] && [ "$RSS" -gt "$MAX_RSS_KB" ]; then
      MAX_RSS_KB=$RSS
    fi
  fi
  sleep 1
done
wait $CURL_PID
IMPORT_ELAPSED=$((SECONDS - IMPORT_START))

# M11.6 — timing and committed:true
COMMITTED=$(python3 -c \
  "import json; b=json.load(open('/tmp/m11_import_result.json')); print(b.get('committed',''))" \
  2>/dev/null)
echo "  Wall clock: ${IMPORT_ELAPSED}s  committed=$COMMITTED"
if [ "$COMMITTED" = "True" ] || [ "$COMMITTED" = "true" ]; then
  if [ "$IMPORT_ELAPSED" -le 40 ]; then
    pass M11.6
  else
    fail M11.6 "${IMPORT_ELAPSED}s — over 40s target (committed=true but too slow)"
  fi
else
  BODY=$(cat /tmp/m11_import_result.json)
  fail M11.6 "committed=$COMMITTED — response: ${BODY:0:200}"
fi

# M11.7 — memory
if [ -n "$SERVER_PID" ] && [ "$MAX_RSS_KB" -gt 0 ]; then
  MAX_RSS_MB=$((MAX_RSS_KB / 1024))
  echo "  Peak server RSS: ${MAX_RSS_MB} MB"
  if [ "$MAX_RSS_MB" -le 500 ]; then
    pass M11.7
  else
    fail M11.7 "Peak RSS ${MAX_RSS_MB} MB — over 500 MB target"
  fi
else
  echo "  ~ SKIP M11.7 — server PID not detected; check memory in Activity Monitor manually"
fi
echo ""

# ── M11.8–M11.14  Import UI (browser — requires :5173 running) ─────────
echo "--- M11.8–M11.14  Import page UI (manual — open http://localhost:5173) ---"
echo ""

manual M11.8 "Sign in as admin@example.com. Confirm 'Import' link is visible in the top nav."
echo "         Expected: link labelled 'Import' appears between 'Bands' and the user name."
echo ""

manual M11.9 "Sign out. Sign in as viewer@example.com. Confirm 'Import' link is ABSENT from nav."
echo "         Expected: nav shows Employees / Analytics / Bands — no Import link."
echo ""

manual M11.10 "While signed in as admin, click Import. Upload a valid 1–5 row CSV and click Preview."
echo "          Expected: summary shows correct rows_valid / rows_total. No spinner stuck."
echo "          Sample CSV (save as test.csv):"
echo "            employee_number,first_name,last_name,email,country_code,department_name,job_title,job_level,hire_date"
echo "            M11UI001,Alice,Smith,m11ui001@example.com,US,Engineering,Engineer,L3,2024-06-01"
echo ""

manual M11.11 "After a successful Preview with no errors, click 'Confirm import'."
echo "          Expected: success banner shows employees_created count. No stuck spinner."
echo ""

manual M11.12 "Upload a CSV where one row has a blank first_name. Click Preview."
echo "          Expected: row error listed (e.g. 'First name can't be blank'). 'Confirm import' button absent."
echo "          Sample bad row: M11UI002,,Smith,m11ui002@example.com,US,Engineering,Engineer,L3,2024-06-01"
echo ""

manual M11.13 "Upload a CSV with the 'email' column removed entirely. Click Preview."
echo "          Expected: header_error message 'missing required column(s): email'. No row errors shown."
echo ""

manual M11.14 "After any successful import, click 'Import another file'."
echo "          Expected: file picker resets to blank (no filename shown, Preview button disabled)."
echo ""

# ── Summary ────────────────────────────────────────────────────────────
echo "================================================================"
echo "  Automated: $PASS passed, $FAIL failed"
echo "  Manual UI: $MANUAL checks require browser (see instructions above)"
echo "================================================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

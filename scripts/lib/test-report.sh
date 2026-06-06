# test-report.sh — shared summary helpers (source from run-tests.sh)

test_report_reset() {
  TEST_REPORT_NAMES=()
  TEST_REPORT_PASS=()
  TEST_REPORT_FAIL=()
  TEST_REPORT_SKIP=()
  TEST_REPORT_SEC=()
  TEST_REPORT_WALL_START=${SECONDS:-0}
}

test_report_add() {
  local name="$1" pass="$2" fail="$3" skip="${4:-0}" duration="${5:-0}"
  TEST_REPORT_NAMES+=("$name")
  TEST_REPORT_PASS+=("$pass")
  TEST_REPORT_FAIL+=("$fail")
  TEST_REPORT_SKIP+=("$skip")
  TEST_REPORT_SEC+=("$duration")
}

test_report_parse_tap() {
  local log="$1"
  local pass fail skip
  pass=$(grep -E '^# pass ' "$log" 2>/dev/null | tail -1 | awk '{print $3}')
  fail=$(grep -E '^# fail ' "$log" 2>/dev/null | tail -1 | awk '{print $3}')
  skip=$(grep -E '^# skip ' "$log" 2>/dev/null | tail -1 | awk '{print $3}')
  pass=${pass:-0}
  fail=${fail:-0}
  skip=${skip:-0}
  printf '%s %s %s' "$pass" "$fail" "$skip"
}

# Parses lines like: == done (auth): 55 passed, 0 failed, 0 skipped ==
test_report_parse_done_lines() {
  local log="$1"
  grep -E '^== done \([^)]+\): [0-9]+ passed' "$log" 2>/dev/null || true
}

test_report_parse_done_line() {
  local line="$1"
  local name pass fail skip
  name=$(printf '%s' "$line" | sed -n 's/^== done (\([^)]*\)): .*$/\1/p')
  pass=$(printf '%s' "$line" | sed -n 's/.*: \([0-9][0-9]*\) passed.*/\1/p')
  fail=$(printf '%s' "$line" | sed -n 's/.*, \([0-9][0-9]*\) failed.*/\1/p')
  skip=$(printf '%s' "$line" | sed -n 's/.*, \([0-9][0-9]*\) skipped.*/\1/p')
  pass=${pass:-0}
  fail=${fail:-0}
  skip=${skip:-0}
  printf '%s %s %s %s' "$name" "$pass" "$fail" "$skip"
}

test_report_print_summary() {
  local total_pass=0 total_fail=0 total_skip=0
  local wall_sec=$((SECONDS - TEST_REPORT_WALL_START))
  local i name pass fail skip sec status
  local overall_status=PASS

  echo ""
  echo "================================================================"
  echo "  cloud-store-893 — test summary"
  echo "================================================================"
  printf "  %-22s %6s %6s %6s %7s\n" "Suite" "Pass" "Fail" "Skip" "Time"
  echo "  ----------------------------------------------------------------"

  for i in "${!TEST_REPORT_NAMES[@]}"; do
    name="${TEST_REPORT_NAMES[$i]}"
    pass="${TEST_REPORT_PASS[$i]}"
    fail="${TEST_REPORT_FAIL[$i]}"
    skip="${TEST_REPORT_SKIP[$i]}"
    sec="${TEST_REPORT_SEC[$i]}"
    if [[ "$fail" -eq 0 ]]; then
      status="PASS"
    else
      status="FAIL"
      overall_status="FAIL"
    fi
    printf "  %-22s %6s %6s %6s %6ss  %s\n" "$name" "$pass" "$fail" "$skip" "$sec" "$status"
    total_pass=$((total_pass + pass))
    total_fail=$((total_fail + fail))
    total_skip=$((total_skip + skip))
  done

  echo "  ----------------------------------------------------------------"
  if [[ "$total_fail" -gt 0 ]]; then
    overall_status="FAIL"
  fi
  printf "  %-22s %6s %6s %6s %6ss  %s\n" "TOTAL" "$total_pass" "$total_fail" "$total_skip" "$wall_sec" "$overall_status"
  echo "================================================================"
  echo ""
}

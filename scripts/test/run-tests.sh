#!/usr/bin/env bash
# run-tests.sh — run tests and print a summary report.
#
# Usage:
#   ./scripts/run-tests.sh                    # unit only (no ORDS)
#   ./scripts/run-tests.sh --integration      # unit + auth + API smoke
#   ./scripts/run-tests.sh --integration --destructive
#   npm test                                    # same as unit-only + summary

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-report.sh
source "$SCRIPT_DIR/../lib/test-report.sh"

cd "$PROJECT_ROOT"

RUN_INTEGRATION=0
RUN_DESTRUCTIVE=no
for arg in "$@"; do
  case "$arg" in
    --integration) RUN_INTEGRATION=1 ;;
    --destructive) RUN_DESTRUCTIVE=yes ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

test_report_reset
OVERALL_FAIL=0

run_unit_suite() {
  local log start_sec elapsed pass fail skip
  log=$(mktemp)
  start_sec=$SECONDS
  echo "== Unit tests =="
  set +e
  node --test test/*.test.js 2>&1 | tee "$log"
  local code=$?
  elapsed=$((SECONDS - start_sec))
  read -r pass fail skip <<< "$(test_report_parse_tap "$log")"
  test_report_add "unit" "$pass" "$fail" "$skip" "$elapsed"
  rm -f "$log"
  if [[ "$code" -ne 0 || "$fail" -gt 0 ]]; then
    OVERALL_FAIL=1
  fi
}

run_integration_suite() {
  local log start_sec elapsed line parsed name pass fail skip
  log=$(mktemp)
  start_sec=$SECONDS
  echo ""
  echo "== Integration tests =="
  set +e
  RUN_DESTRUCTIVE="$RUN_DESTRUCTIVE" "$SCRIPT_DIR/run-integration-tests.sh" 2>&1 | tee "$log"
  local code=$?
  elapsed=$((SECONDS - start_sec))

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -r name pass fail skip <<< "$(test_report_parse_done_line "$line")"
    test_report_add "$name" "$pass" "$fail" "$skip" "$elapsed"
    if [[ "$fail" -gt 0 ]]; then
      OVERALL_FAIL=1
    fi
  done < <(test_report_parse_done_lines "$log")

  if [[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]]; then
    declare -A SUITE_TIMES=()
    while IFS= read -r tline; do
      local tname tsec
      tname=$(printf '%s' "$tline" | sed -n 's/^== timing (\([^)]*\)): \([0-9][0-9]*\).*$/\1/p')
      tsec=$(printf '%s' "$tline" | sed -n 's/^== timing (\([^)]*\)): \([0-9][0-9]*\).*$/\2/p')
      [[ -n "$tname" && -n "$tsec" ]] && SUITE_TIMES["$tname"]="$tsec"
    done < <(grep -E '^== timing \([^)]+\): [0-9]+' "$log" 2>/dev/null || true)

    local idx tname
    for idx in "${!TEST_REPORT_NAMES[@]}"; do
      tname="${TEST_REPORT_NAMES[$idx]}"
      if [[ -n "${SUITE_TIMES[$tname]+set}" ]]; then
        TEST_REPORT_SEC[$idx]="${SUITE_TIMES[$tname]}"
      fi
    done
  else
    while IFS= read -r tline; do
      local tname tsec idx
      tname=$(printf '%s' "$tline" | sed -n 's/^== timing (\([^)]*\)): \([0-9][0-9]*\).*$/\1/p')
      tsec=$(printf '%s' "$tline" | sed -n 's/^== timing (\([^)]*\)): \([0-9][0-9]*\).*$/\2/p')
      [[ -z "$tname" || -z "$tsec" ]] && continue
      for idx in "${!TEST_REPORT_NAMES[@]}"; do
        if [[ "${TEST_REPORT_NAMES[$idx]}" == "$tname" ]]; then
          TEST_REPORT_SEC[$idx]="$tsec"
        fi
      done
    done < <(grep -E '^== timing \([^)]+\): [0-9]+' "$log" 2>/dev/null || true)
  fi

  if ! test_report_parse_done_lines "$log" | grep -q .; then
    test_report_add "integration" 0 1 0 "$elapsed"
    OVERALL_FAIL=1
  fi

  rm -f "$log"
  if [[ "$code" -ne 0 ]]; then
    OVERALL_FAIL=1
  fi
}

run_unit_suite

if [[ "$RUN_INTEGRATION" == "1" ]]; then
  run_integration_suite
fi

test_report_print_summary

if [[ "$OVERALL_FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1

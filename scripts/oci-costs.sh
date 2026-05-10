#!/bin/zsh
# oci-costs.sh — Show OCI spend for a date range, grouped by service or compartment.
#
# Examples:
#   ./scripts/oci-costs.sh                       # month-to-date, by service
#   ./scripts/oci-costs.sh --prev-month          # previous full month
#   ./scripts/oci-costs.sh --week --total        # last 7 days, single total
#   ./scripts/oci-costs.sh --by-compartment      # month-to-date, by compartment
#   ./scripts/oci-costs.sh --since 2026-01-01 --until 2026-05-01

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo "${BLUE}ℹ️  $1${NC}" }
success() { echo "${GREEN}✅ $1${NC}" }
warn()    { echo "${YELLOW}⚠️  $1${NC}" }
error()   { echo "${RED}❌ $1${NC}"; exit 1 }

GROUP_BY="service"
SCOPE="month"
SINCE=""
UNTIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --month)               SCOPE="month";      shift ;;
    --prev-month|--last-month) SCOPE="prev-month"; shift ;;
    --week)                SCOPE="week";       shift ;;
    --today)               SCOPE="today";      shift ;;
    --by-service)          GROUP_BY="service";          shift ;;
    --by-compartment)      GROUP_BY="compartmentName";  shift ;;
    --total)               GROUP_BY="";        shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) error "Unknown flag: $1 (use --help)" ;;
  esac
done

command -v oci >/dev/null || error "oci CLI not found. Run: brew install oci-cli"

# ── Date range resolution (BSD date / macOS) ─────────────────────────────────
if [[ -z "$SINCE" || -z "$UNTIL" ]]; then
  case "$SCOPE" in
    month)
      SINCE="${SINCE:-$(date -u +%Y-%m-01)}"
      UNTIL="${UNTIL:-$(date -u -v+1d +%Y-%m-%d)}"
      ;;
    prev-month)
      SINCE="${SINCE:-$(date -u -v-1m +%Y-%m-01)}"
      UNTIL="${UNTIL:-$(date -u +%Y-%m-01)}"
      ;;
    week)
      SINCE="${SINCE:-$(date -u -v-7d +%Y-%m-%d)}"
      UNTIL="${UNTIL:-$(date -u -v+1d +%Y-%m-%d)}"
      ;;
    today)
      SINCE="${SINCE:-$(date -u +%Y-%m-%d)}"
      UNTIL="${UNTIL:-$(date -u -v+1d +%Y-%m-%d)}"
      ;;
  esac
fi

TIME_FROM="${SINCE}T00:00:00Z"
TIME_TO="${UNTIL}T00:00:00Z"

# ── Tenancy OCID ──────────────────────────────────────────────────────────────
TENANCY=$(oci iam tenancy get --query 'data.id' --raw-output 2>/dev/null || true)
if [[ -z "$TENANCY" ]]; then
  TENANCY=$(grep -E '^tenancy=' "$HOME/.oci/config" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' "')
fi
[[ -z "$TENANCY" ]] && error "Could not determine tenancy OCID. Check ~/.oci/config or run: oci setup config"

# ── group_by JSON argument ────────────────────────────────────────────────────
if [[ -n "$GROUP_BY" ]]; then
  GROUP_BY_ARG="[\"$GROUP_BY\"]"
  GROUP_LABEL="$GROUP_BY"
else
  GROUP_BY_ARG="[]"
  GROUP_LABEL="(total)"
fi

echo
info "Tenancy:  $TENANCY"
info "Range:    $TIME_FROM  →  $TIME_TO"
info "Group by: $GROUP_LABEL"
echo

# ── Fetch cost data ───────────────────────────────────────────────────────────
RAW=$(oci usage-api usage-summary request-summarized-usages \
  --tenant-id "$TENANCY" \
  --time-usage-started "$TIME_FROM" \
  --time-usage-ended   "$TIME_TO" \
  --granularity MONTHLY \
  --query-type COST \
  --group-by "$GROUP_BY_ARG" \
  2>/dev/null) || error "OCI usage-api call failed. Check OCI CLI auth and the tenancy permissions."

# ── Format output ─────────────────────────────────────────────────────────────
# Use python (always present on macOS) instead of relying on jq.
python3 - "$RAW" "$GROUP_BY" <<'PY'
import json, sys, collections
raw, group_key = sys.argv[1], sys.argv[2]
data = json.loads(raw or "{}")
items = data.get("data", {}).get("items", [])
if not items:
    print("  (no usage records in this range — likely $0.00 / Always Free)")
    sys.exit(0)

by_key = collections.defaultdict(float)
currency = ""
for it in items:
    amt = it.get("computed-amount") or 0
    try:
        amt = float(amt)
    except (TypeError, ValueError):
        amt = 0.0
    currency = it.get("currency") or currency
    if group_key:
        # Map JMES-style key back to JSON field
        json_key = {
            "service": "service",
            "compartmentName": "compartment-name",
        }.get(group_key, group_key)
        label = it.get(json_key) or "(unknown)"
    else:
        label = "TOTAL"
    by_key[label] += amt

label_w = max(len(k) for k in by_key) if by_key else 10
total = sum(by_key.values())
print(f"  {'Group'.ljust(label_w)}    Amount   Currency")
print(f"  {'-'*label_w}    -------  --------")
for k, v in sorted(by_key.items(), key=lambda x: -x[1]):
    print(f"  {k.ljust(label_w)}    {v:>7.4f}  {currency}")
print(f"  {'-'*label_w}    -------  --------")
print(f"  {'TOTAL'.ljust(label_w)}    {total:>7.4f}  {currency}")
PY

echo

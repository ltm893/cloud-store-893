#!/usr/bin/env bash
# List AWS resources for the cloud-store-893 terraform-aws stack.
#
# Usage:
#   ./scripts/aws/list-resources.sh
#   ./scripts/aws/list-resources.sh --region us-east-1
#   ./scripts/aws/list-resources.sh --json
#
# Prefers terraform outputs when state exists; also discovers resources tagged
# Project=cloud-store-893 ManagedBy=terraform-aws (works even if state is empty
# after a partial destroy).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="${ROOT}/terraform-aws"
REGION=""
JSON=0

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REGION" && -f "${TF_DIR}/terraform.tfvars" ]]; then
  REGION="$(awk -F= '/^[[:space:]]*aws_region[[:space:]]*=/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    gsub(/^"|"$/, "", $2)
    print $2
    exit
  }' "${TF_DIR}/terraform.tfvars")"
fi
REGION="${REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  echo "AWS credentials not available (aws sts get-caller-identity failed)." >&2
  exit 1
fi

echo "Account:  ${ACCOUNT_ID}"
echo "Region:   ${REGION}"
echo "Project:  cloud-store-893 (ManagedBy=terraform-aws)"
echo ""

# ── Terraform outputs (if state present) ─────────────────────────────────────
TF_OUT_JSON=""
if [[ -d "${TF_DIR}/.terraform" ]] || [[ -f "${TF_DIR}/terraform.tfstate" ]] || [[ -f "${TF_DIR}/.terraform/terraform.tfstate" ]]; then
  if (cd "$TF_DIR" && terraform output -json >/dev/null 2>&1); then
    TF_OUT_JSON="$(cd "$TF_DIR" && terraform output -json 2>/dev/null || true)"
  fi
fi

if [[ -n "$TF_OUT_JSON" && "$TF_OUT_JSON" != "{}" ]]; then
  echo "Terraform outputs (${TF_DIR##*/}):"
  echo "────────────────────────────────────────"
  echo "$TF_OUT_JSON" | python3 -c '
import sys, json
o = json.load(sys.stdin)
keys = [
  ("app_url", "App URL"),
  ("alb_dns_name", "ALB DNS"),
  ("ecs_cluster_name", "ECS cluster"),
  ("ecs_service_name", "ECS service"),
  ("ecr_repository_url", "ECR repo"),
  ("rds_endpoint", "RDS endpoint"),
  ("dynamodb_table_name", "DynamoDB table"),
  ("image_tag", "Image tag"),
]
for key, label in keys:
  if key in o and o[key].get("value") is not None:
    print(f"  {label:<16} {o[key]['value']}")
'
  echo ""
else
  echo "Terraform outputs: (none — stack not applied, or no local state)"
  echo ""
fi

# ── Live status for core services (when named via terraform) ─────────────────
if [[ -n "$TF_OUT_JSON" && "$TF_OUT_JSON" != "{}" ]]; then
  CLUSTER="$(echo "$TF_OUT_JSON" | python3 -c 'import sys,json; o=json.load(sys.stdin); print(o.get("ecs_cluster_name",{}).get("value") or "")')"
  SERVICE="$(echo "$TF_OUT_JSON" | python3 -c 'import sys,json; o=json.load(sys.stdin); print(o.get("ecs_service_name",{}).get("value") or "")')"
  DDB="$(echo "$TF_OUT_JSON" | python3 -c 'import sys,json; o=json.load(sys.stdin); print(o.get("dynamodb_table_name",{}).get("value") or "")')"

  if [[ -n "$CLUSTER" && -n "$SERVICE" ]]; then
    echo "ECS service status:"
    echo "────────────────────────────────────────"
    aws ecs describe-services \
      --region "$REGION" \
      --cluster "$CLUSTER" \
      --services "$SERVICE" \
      --query 'services[0].{status:status,running:runningCount,desired:desiredCount,pending:pendingCount,taskDef:taskDefinition}' \
      --output table 2>/dev/null || echo "  (service not found)"
    echo ""
  fi

  if [[ -n "$DDB" ]]; then
    echo "DynamoDB:"
    echo "────────────────────────────────────────"
    aws dynamodb describe-table \
      --region "$REGION" \
      --table-name "$DDB" \
      --query 'Table.{name:TableName,status:TableStatus,itemCount:ItemCount,bytes:TableSizeBytes,billing:BillingModeSummary.BillingMode}' \
      --output table 2>/dev/null || echo "  (table not found)"
    echo ""
  fi
fi

# RDS by Project tag (identifier is not a terraform output)
echo "RDS instances (tagged Project=cloud-store-893):"
echo "────────────────────────────────────────"
RDS_JSON="$(aws rds describe-db-instances --region "$REGION" --output json 2>/dev/null || echo '{"DBInstances":[]}')"
echo "$RDS_JSON" | python3 -c '
import sys, json
dbs = [
  d for d in (json.load(sys.stdin).get("DBInstances") or [])
  if any(t.get("Key") == "Project" and t.get("Value") == "cloud-store-893" for t in (d.get("TagList") or []))
]
if not dbs:
  print("  (none)")
else:
  for d in dbs:
    ep = (d.get("Endpoint") or {}).get("Address") or "-"
    ident = d.get("DBInstanceIdentifier") or "?"
    cls = d.get("DBInstanceClass") or "?"
    status = d.get("DBInstanceStatus") or "?"
    engine = d.get("Engine") or "?"
    print(f"  {ident:<36} {cls:<14} {status:<12} {engine:<10} {ep}")
'
echo ""

# ── Tagged resource inventory ────────────────────────────────────────────────
echo "Tagged resources (Project=cloud-store-893, ManagedBy=terraform-aws):"
echo "────────────────────────────────────────"

TAGGED="$(aws resourcegroupstaggingapi get-resources \
  --region "$REGION" \
  --tag-filters \
    Key=Project,Values=cloud-store-893 \
    Key=ManagedBy,Values=terraform-aws \
  --output json 2>/dev/null || echo '{"ResourceTagMappingList":[]}')"

if [[ "$JSON" -eq 1 ]]; then
  echo "$TAGGED" | python3 -m json.tool
  exit 0
fi

COUNT="$(echo "$TAGGED" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("ResourceTagMappingList") or []))')"

if [[ "$COUNT" == "0" ]]; then
  echo "No tagged resources found — stack is destroyed or not deployed in ${REGION}."
else
  echo "$TAGGED" | python3 -c '
import sys, json
data = json.load(sys.stdin)
items = data.get("ResourceTagMappingList") or []

def short_type(arn: str) -> str:
    # arn:aws:service:region:account:… → service / resource-type
    parts = arn.split(":", 5)
    if len(parts) < 6:
        return "?"
    service = parts[2]
    rest = parts[5]
    if "/" in rest:
        rtype = rest.split("/", 1)[0]
    elif ":" in rest:
        rtype = rest.split(":", 1)[0]
    else:
        rtype = rest
    return f"{service}:{rtype}"

def short_name(arn: str) -> str:
    return arn.rsplit("/", 1)[-1] if "/" in arn else arn.rsplit(":", 1)[-1]

rows = []
for r in items:
    arn = r.get("ResourceARN") or ""
    tags = {t["Key"]: t["Value"] for t in (r.get("Tags") or [])}
    rows.append((short_type(arn), tags.get("Name") or short_name(arn), arn))

rows.sort(key=lambda x: (x[0], x[1]))
for rtype, name, arn in rows:
    print(f"  {rtype:<40} {name}")
print()
print(f"Total: {len(rows)} tagged resource(s)")
'
fi

echo ""

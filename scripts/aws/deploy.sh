#!/usr/bin/env bash
# Deploy cloud-store-893 to AWS (parallel to OCI). See docs/aws-deploy.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="${ROOT}/terraform-aws"

cd "$TF_DIR"

if [[ ! -f terraform.tfvars ]]; then
  echo "Missing ${TF_DIR}/terraform.tfvars — copy terraform.tfvars.example and edit."
  exit 1
fi

echo "==> terraform init"
terraform init -input=false

echo "==> Phase 1: network + ECR (so we can push an image before ECS starts)"
terraform apply -input=false -auto-approve \
  -target=aws_ecr_repository.app \
  -target=aws_ecr_lifecycle_policy.app \
  -target=aws_vpc.main \
  -target=aws_subnet.public \
  -target=aws_subnet.private \
  -target=aws_internet_gateway.main \
  -target=aws_eip.nat \
  -target=aws_nat_gateway.main \
  -target=aws_route_table.public \
  -target=aws_route_table.private \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_security_group.alb \
  -target=aws_security_group.ecs \
  -target=aws_security_group.rds

ECR_URL="$(terraform output -raw ecr_repository_url 2>/dev/null || true)"
if [[ -z "${ECR_URL}" ]]; then
  # output may not exist until full apply; read from targeted state
  ECR_URL="$(terraform state show -json aws_ecr_repository.app | jq -r '.values.attributes.repository_url')"
fi

REGION="$(grep -E '^aws_region' terraform.tfvars | awk -F'=|"' '{print $3}' | tr -d ' "')"
REGION="${REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
IMAGE_TAG="deploy-$(date -u +%Y%m%d%H%M%S)"

echo "==> ECR login (${REGION})"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Build & push ${ECR_URL}:${IMAGE_TAG} (linux/arm64)"
cd "$ROOT"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
docker build \
  --platform linux/arm64 \
  --build-arg "BUILD_ID=${IMAGE_TAG}" \
  --build-arg "BUILD_LABEL=aws deploy" \
  --build-arg "GIT_SHA=${GIT_SHA}" \
  --build-arg "TARGETARCH=arm64" \
  -t "${ECR_URL}:${IMAGE_TAG}" \
  -t "${ECR_URL}:latest" \
  .
docker push "${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:latest"

echo "==> Phase 2: full stack with image_tag=${IMAGE_TAG}"
cd "$TF_DIR"
terraform apply -input=false -auto-approve -var="image_tag=${IMAGE_TAG}"

ECR_URL="$(terraform output -raw ecr_repository_url)"
APP_URL="$(terraform output -raw app_url)"
CLUSTER="$(terraform output -raw ecs_cluster_name)"
MIGRATE_TD="$(terraform output -raw migrate_task_definition_arn)"
SUBNET_JSON="$(terraform output -json private_subnet_ids)"
ECS_SG="$(terraform output -raw ecs_security_group_id)"
REGION="$(terraform output -raw aws_region)"
SERVICE="$(terraform output -raw ecs_service_name)"

# Build network config JSON for run-task
NETWORK_CONFIG="$(jq -nc \
  --argjson subnets "$SUBNET_JSON" \
  --arg sg "$ECS_SG" \
  '{awsvpcConfiguration:{subnets:$subnets,securityGroups:[$sg],assignPublicIp:"DISABLED"}}')"

echo "==> Run DB migrate (schema + seed)"
TASK_ARN="$(aws ecs run-task \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --task-definition "$MIGRATE_TD" \
  --network-configuration "$NETWORK_CONFIG" \
  --query 'tasks[0].taskArn' \
  --output text)"

echo "Migrate task: ${TASK_ARN}"
aws ecs wait tasks-stopped --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK_ARN"
EXIT_CODE="$(aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)"
if [[ "$EXIT_CODE" != "0" ]]; then
  echo "Migrate failed with exit code ${EXIT_CODE}"
  aws logs tail "/ecs/cloud-store-893-dev" --region "$REGION" --since 15m --filter-pattern migrate 2>/dev/null || true
  exit 1
fi

echo "==> Force new ECS deployment (post-migrate)"
aws ecs update-service \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment \
  >/dev/null

echo "==> Waiting for service stability"
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"

echo ""
echo "Deploy complete."
echo "  App URL:  ${APP_URL}"
echo "  Image:    ${ECR_URL}:${IMAGE_TAG}"
echo "  Smoke:    curl -sS ${APP_URL}api/build-info"

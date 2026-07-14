#!/usr/bin/env bash
# Rebuild/push app image and force ECS redeploy (no full terraform recreate).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="${ROOT}/terraform-aws"

cd "$TF_DIR"
terraform init -input=false >/dev/null

ECR_URL="$(terraform output -raw ecr_repository_url)"
CLUSTER="$(terraform output -raw ecs_cluster_name)"
SERVICE="$(terraform output -raw ecs_service_name)"
REGION="$(terraform output -raw aws_region)"
FAMILY="$(terraform output -raw ecs_task_definition_family)"
APP_URL="$(terraform output -raw app_url)"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
IMAGE_TAG="deploy-$(date -u +%Y%m%d%H%M%S)"

echo "==> ECR login"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Build & push ${ECR_URL}:${IMAGE_TAG}"
cd "$ROOT"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
docker build \
  --platform linux/arm64 \
  --build-arg "BUILD_ID=${IMAGE_TAG}" \
  --build-arg "BUILD_LABEL=aws redeploy" \
  --build-arg "GIT_SHA=${GIT_SHA}" \
  --build-arg "TARGETARCH=arm64" \
  -t "${ECR_URL}:${IMAGE_TAG}" \
  -t "${ECR_URL}:latest" \
  .
docker push "${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:latest"

echo "==> Register new task definition revision with new image"
TASK_DEF_JSON="$(aws ecs describe-task-definition --region "$REGION" --task-definition "$FAMILY" \
  --query 'taskDefinition' --output json)"

NEW_TD="$(echo "$TASK_DEF_JSON" | jq --arg IMAGE "${ECR_URL}:${IMAGE_TAG}" '
  .containerDefinitions[0].image = $IMAGE
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
')"

NEW_ARN="$(aws ecs register-task-definition --region "$REGION" --cli-input-json "$NEW_TD" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"

echo "==> Update service → ${NEW_ARN}"
aws ecs update-service \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$NEW_ARN" \
  --force-new-deployment \
  >/dev/null

aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"

echo "Redeploy complete: ${APP_URL}  image=${IMAGE_TAG}"

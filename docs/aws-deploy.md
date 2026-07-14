# AWS deploy — cloud-store-893

Parallel environment next to OCI. **OCI stays as-is**; this stack does not modify `terraform/` or `oci.cloudstore893.com`.

| | OCI (existing) | AWS (this doc) |
|--|----------------|----------------|
| URL | `https://oci.cloudstore893.com/` | `https://aws.cloudstore893.com/` |
| Compute | Container Instance | ECS Fargate (ARM64) |
| DB | Autonomous DB + ORDS | Aurora PostgreSQL Serverless v2 |
| App env | `ORDS_BASE_URL` | `DATA_BACKEND=postgres` + `DATABASE_URL` |
| Auth (v1) | PIN + optional IdP | **PIN only** (Cognito later) |
| IaC | `terraform/` | `terraform-aws/` |

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity`)
- Terraform ≥ 1.5
- Docker (build/push to ECR)
- `jq`
- Route 53 public hosted zone for `cloudstore893.com` (already used for OCI delegation)

## One-time setup

```bash
cd terraform-aws
cp terraform.tfvars.example terraform.tfvars
# Edit PINs / hostname if needed
```

## Full deploy

```bash
./scripts/aws/deploy.sh
```

What it does:

1. `terraform apply` — VPC, NAT, ECR, Aurora, Secrets Manager, ACM, ALB, ECS, Route 53 `aws.cloudstore893.com`
2. Builds `linux/arm64` image and pushes to ECR
3. Re-applies with the new `image_tag`
4. Runs a one-shot ECS migrate task (`scripts/db/postgres/migrate.js` — schema + seed)
5. Waits for the ECS service to stabilize

Smoke:

```bash
curl -sS https://aws.cloudstore893.com/api/build-info
# expect dataBackend: "postgres"
```

PIN unlock (cashier defaults from tfvars / Secrets Manager):

```bash
curl -sS -X POST https://aws.cloudstore893.com/api/cashier/unlock \
  -H 'Content-Type: application/json' \
  -d '{"pin":"8930"}' -c /tmp/aws-cashier.txt
```

## Redeploy app code only

```bash
./scripts/aws/redeploy-app-code.sh
```

## Local Postgres (dual-backend dev)

```bash
docker compose up -d postgres
export DATA_BACKEND=postgres
export DATABASE_URL=postgresql://cloudstore:cloudstore@127.0.0.1:5432/cloudstore
export DATABASE_SSL=false
./scripts/db/postgres/migrate.sh
npm start
```

OCI/local ORDS continues to work with the default `DATA_BACKEND=ords` + `ORDS_BASE_URL`.

## Cost note

Dev-sized stack (single NAT, Fargate 0.5 vCPU / 1 GB, Aurora ~0.5 ACU) is roughly **$110–160/mo** in `us-east-1` when left running 24/7. Tear down with `cd terraform-aws && terraform destroy` when not needed.

## Cognito

Not wired in v1. Node OIDC helpers remain for OCI; AWS task definition leaves IdP env unset and relies on PIN unlock.

## Tablet apps

Default Android/iOS builds still target OCI. To test AWS, rebuild with `API_BASE_URL=https://aws.cloudstore893.com/` (Android) or update the iOS xcconfig accordingly.

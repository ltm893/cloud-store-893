# AWS deploy — cloud-store-893

Parallel environment next to OCI. **OCI stays as-is**; this stack does not modify `terraform/` or `oci.cloudstore893.com`.

| | OCI (existing) | AWS (this doc) |
|--|----------------|----------------|
| URL | `https://oci.cloudstore893.com/` | `https://aws.cloudstore893.com/` |
| Compute | Container Instance | ECS Fargate (ARM64) |
| DB | Autonomous DB + ORDS | **RDS PostgreSQL** + **DynamoDB** (hybrid) |
| App env | `ORDS_BASE_URL` | `DATA_BACKEND=hybrid` + `DATABASE_URL` + `DYNAMODB_TABLE` |
| Auth (v1) | PIN + optional IdP | **PIN only** (Cognito later) |
| IaC | `terraform/` | `terraform-aws/` |

## Hybrid map (phase B)

| DynamoDB | RDS Postgres |
|----------|--------------|
| Sessions (TTL) | `sales` / `sale_items` / `sale_payments` |
| Live carts | Inventory + movements |
| Product cache (TTL) | Tills / pos_sessions / approvals |
| Event logs | Customers, products (source of truth) |

**Phase A later:** DynamoDB `OFFLINE#…` / `ORDER#…` keys (reserved in `lib/dynamo/keys.js`) + server drain into Postgres checkout. Tablets keep local offline queues for now.

## Cost control

`terraform apply` when you need the env; **`terraform destroy` when idle**. After a clean destroy you should not pay for RDS/NAT/ALB/Fargate/Dynamo for this stack.

Rough cost **while up** (us-east-1): RDS `db.t4g.micro` ~$14–20 + NAT ~$32 + ALB ~$16–22 + Dynamo pennies + Fargate while tasks run.

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity`)
- Terraform ≥ 1.5
- Docker (build/push to ECR)
- `jq`
- Route 53 public hosted zone for `cloudstore893.com`

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

Smoke:

```bash
curl -sS https://aws.cloudstore893.com/api/build-info
# expect dataBackend: "hybrid", hybrid: true
```

## Redeploy app code only

```bash
./scripts/aws/redeploy-app-code.sh
```

## List resources

```bash
./scripts/aws/list-resources.sh
# ./scripts/aws/list-resources.sh --region us-east-1
# ./scripts/aws/list-resources.sh --json
```

Shows terraform outputs (if state exists), ECS/RDS/Dynamo status, and all resources tagged `Project=cloud-store-893` / `ManagedBy=terraform-aws`.

## Tear down

```bash
cd terraform-aws && terraform destroy
```

## Local Postgres (SQL-only, not full hybrid)

```bash
docker compose up -d postgres
export DATA_BACKEND=postgres
export DATABASE_URL=postgresql://cloudstore:cloudstore@127.0.0.1:5432/cloudstore
export DATABASE_SSL=false
./scripts/db/postgres/migrate.sh
npm start
```

Local hybrid (optional):

```bash
docker compose --profile hybrid up -d
export DATA_BACKEND=hybrid SESSION_BACKEND=dynamo
export DATABASE_URL=postgresql://cloudstore:cloudstore@127.0.0.1:5432/cloudstore
export DATABASE_SSL=false
export DYNAMODB_TABLE=cloud-store-893-dev
export DYNAMODB_ENDPOINT=http://127.0.0.1:8000
export AWS_REGION=us-east-1
# Create the local table once (PK=pk, SK=sk, TTL=expiresAt) then:
./scripts/db/postgres/migrate.sh
npm start
```

OCI/local ORDS continues with default `DATA_BACKEND=ords` + `ORDS_BASE_URL`.

## Cognito

Not wired in v1.

## Tablet apps

Default builds still target OCI. To test AWS, rebuild with `API_BASE_URL=https://aws.cloudstore893.com/`.

# terraform-aws

AWS provider stack for the parallel POS environment at `aws.cloudstore893.com`.

Does **not** share state with `../terraform` (OCI).

## Hybrid data plane

| Store | Holds |
|-------|--------|
| **RDS PostgreSQL** (`db.t4g.micro`) | Sales, inventory, tills/settlements |
| **DynamoDB** (on-demand) | Sessions, carts, product cache, event logs |

App env: `DATA_BACKEND=hybrid`, `SESSION_BACKEND=dynamo`, `DYNAMODB_TABLE`, `DATABASE_URL`.

## Cost control

Use `terraform apply` when needed and `terraform destroy` when idle — almost all stack cost stops when destroyed.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider, AZs |
| `network.tf` | VPC, public/private subnets, NAT, security groups |
| `ecr.tf` | Container registry |
| `rds.tf` | RDS PostgreSQL |
| `dynamodb.tf` | DynamoDB table + task IAM |
| `secrets.tf` | DB + PIN secrets |
| `alb.tf` | ALB + ACM |
| `ecs.tf` | Fargate service + migrate task def |
| `dns.tf` | Route 53 alias |
| `variables.tf` / `outputs.tf` | Inputs / outputs |

## Usage

See [docs/aws-deploy.md](../docs/aws-deploy.md). Prefer `./scripts/aws/deploy.sh` over raw apply so the image and migrate job run.

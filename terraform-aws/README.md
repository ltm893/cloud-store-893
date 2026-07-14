# terraform-aws

AWS provider stack for the parallel POS environment at `aws.cloudstore893.com`.

Does **not** share state with `../terraform` (OCI).

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider, AZs |
| `network.tf` | VPC, public/private subnets, NAT, security groups |
| `ecr.tf` | Container registry |
| `aurora.tf` | Aurora PostgreSQL Serverless v2 |
| `secrets.tf` | DB + PIN secrets |
| `alb.tf` | ALB + ACM |
| `ecs.tf` | Fargate service + migrate task def |
| `dns.tf` | Route 53 alias |
| `variables.tf` / `outputs.tf` | Inputs / outputs |

## Usage

See [docs/aws-deploy.md](../docs/aws-deploy.md). Prefer `./scripts/aws/deploy.sh` over raw apply so the image and migrate job run.

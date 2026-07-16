output "app_url" {
  description = "HTTPS URL for the AWS POS/admin app"
  value       = "https://${var.app_hostname}/"
}

output "alb_dns_name" {
  description = "ALB DNS name (use if Route 53 record is disabled)"
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for app images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_family" {
  description = "App task definition family"
  value       = aws_ecs_task_definition.app.family
}

output "migrate_task_definition_arn" {
  description = "Migrate task definition ARN"
  value       = aws_ecs_task_definition.migrate.arn
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (non-secret host)"
  value       = aws_db_instance.main.address
}

output "rds_db_name" {
  description = "RDS database name"
  value       = var.db_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table for sessions/carts/cache/events"
  value       = aws_dynamodb_table.app.name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = aws_secretsmanager_secret.db.arn
}

output "app_pins_secret_arn" {
  description = "Secrets Manager ARN for PIN credentials"
  value       = aws_secretsmanager_secret.app_pins.arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for one-shot migrate tasks)"
  value       = aws_subnet.private[*].id
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = aws_security_group.ecs.id
}

output "aws_region" {
  description = "Deployed region"
  value       = var.aws_region
}

output "image_tag" {
  description = "Current image tag configured in Terraform"
  value       = var.image_tag
}

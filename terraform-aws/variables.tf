variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short name used in resource names"
  type        = string
  default     = "cloud-store-893"
}

variable "app_hostname" {
  description = "Public hostname for the ALB (ACM + Route 53)"
  type        = string
  default     = "aws.cloudstore893.com"
}

variable "route53_zone_name" {
  description = "Parent Route 53 hosted zone name (must already exist)"
  type        = string
  default     = "cloudstore893.com"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.89.0.0/16"
}

variable "cashier_pin" {
  description = "Cashier PIN for POS unlock"
  type        = string
  sensitive   = true
  default     = "8930"
}

variable "admin_pin" {
  description = "Admin PIN for /admin/ (defaults to cashier_pin if empty)"
  type        = string
  sensitive   = true
  default     = "8930"
}

variable "image_tag" {
  description = "ECR image tag for the ECS service"
  type        = string
  default     = "latest"
}

variable "fargate_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU, 512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "fargate_memory" {
  description = "Fargate task memory (MB)"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "ECS service desired task count"
  type        = number
  default     = 1
}

variable "db_instance_class" {
  description = "RDS PostgreSQL instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial RDS database name"
  type        = string
  default     = "cloudstore"
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
  default     = "cloudstore"
}

variable "create_dns_record" {
  description = "Create Route 53 alias for app_hostname"
  type        = bool
  default     = true
}

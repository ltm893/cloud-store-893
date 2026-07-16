resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-rds"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_master_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
  backup_retention_period = 0
  copy_tags_to_snapshot   = false

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}

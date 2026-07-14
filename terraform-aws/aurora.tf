resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-aurora"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-aurora"
  }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${local.name_prefix}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.4"
  database_name      = var.db_name
  master_username    = var.db_master_username
  master_password    = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  storage_encrypted   = true
  skip_final_snapshot = true
  apply_immediately   = true
  deletion_protection = false

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  tags = {
    Name = "${local.name_prefix}-aurora"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  publicly_accessible = false

  tags = {
    Name = "${local.name_prefix}-aurora-writer"
  }
}

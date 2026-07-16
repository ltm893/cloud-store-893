resource "random_password" "db" {
  length  = 32
  special = true
  # Avoid URL delimiter characters so DATABASE_URL stays parseable
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/db"
  description             = "RDS PostgreSQL credentials and connection info"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    engine   = "postgres"
    url      = "postgresql://${var.db_master_username}:${urlencode(random_password.db.result)}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}"
  })
}

resource "aws_secretsmanager_secret" "app_pins" {
  name                    = "${local.name_prefix}/app-pins"
  description             = "Cashier and admin PIN credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_pins" {
  secret_id = aws_secretsmanager_secret.app_pins.id
  secret_string = jsonencode({
    CASHIER_PIN = var.cashier_pin
    ADMIN_PIN   = var.admin_pin != "" ? var.admin_pin : var.cashier_pin
  })
}

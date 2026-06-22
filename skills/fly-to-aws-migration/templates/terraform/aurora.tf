# Aurora Serverless v2 Postgres.
# 0.5-4 ACU range = $58-466/mo compute. Average usage ~1 ACU = $117/mo.
#
# 🟡 For very low traffic (dev/staging), consider RDS db.t4g.micro instead.

# Subnet group across private subnets
resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-aurora-subnets"
  subnet_ids = aws_subnet.private[*].id
}

# Security group — only ECS tasks can connect
resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Aurora — allow from ECS tasks only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}

# KMS key for encryption at rest
resource "aws_kms_key" "aurora" {
  description             = "${local.name_prefix} Aurora encryption"
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${local.name_prefix}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

# Random admin password (rotate after launch)
resource "random_password" "aurora_admin" {
  length  = 32
  special = false  # avoid URL-encoding issues
}

# ── Cluster ──
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${local.name_prefix}-aurora"

  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"  # required for Serverless v2
  engine_version = "17.4"

  database_name   = replace(var.project, "-", "_")
  master_username = "admin"
  master_password = random_password.aurora_admin.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  backup_retention_period   = 7
  preferred_backup_window   = "16:00-17:00"  # UTC

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-aurora-final"

  serverlessv2_scaling_configuration {
    min_capacity = 0.5  # 🟡 Min charge $58/mo (changing to 0 in some regions)
    max_capacity = 4.0
  }

  lifecycle {
    ignore_changes = [
      master_password,   # rotate manually after creation
      engine_version     # patch independently
    ]
  }
}

# ── Instance ──
resource "aws_rds_cluster_instance" "main" {
  identifier         = "${local.name_prefix}-aurora-1"
  cluster_identifier = aws_rds_cluster.main.id

  instance_class = "db.serverless"
  engine         = aws_rds_cluster.main.engine
  engine_version = aws_rds_cluster.main.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 0  # set to 60 for Enhanced Monitoring (costs more)
}

# Store admin URL in Secrets Manager
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/${var.environment}/db"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    DATABASE_URL = "postgresql://admin:${random_password.aurora_admin.result}@${aws_rds_cluster.main.endpoint}:5432/${aws_rds_cluster.main.database_name}?sslmode=no-verify"
    DATABASE_HOST = aws_rds_cluster.main.endpoint
    DATABASE_PORT = "5432"
    DATABASE_NAME = aws_rds_cluster.main.database_name
    DATABASE_USER = "admin"
    DATABASE_PASSWORD = random_password.aurora_admin.result
  })

  lifecycle {
    ignore_changes = [secret_string]  # allow manual updates without TF reverting
  }
}

output "aurora_endpoint" { value = aws_rds_cluster.main.endpoint }
output "aurora_reader_endpoint" { value = aws_rds_cluster.main.reader_endpoint }
output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }

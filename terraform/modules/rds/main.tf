resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    {
      Name = "${var.project_name}-db-subnet-group"
    },
    var.tags
  )
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "${var.project_name}-rds-sg"
    },
    var.tags
  )
}

# Random password for RDS
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AWS Secrets Manager Secret for RDS
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-db-password"
  description = "RDS database password for ${var.project_name}"
  
  # Ensure the secret is deleted when the RDS is deleted
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "db_endpoint" {
  name        = "${var.project_name}-db-endpoint"
  description = "RDS database endpoint for ${var.project_name}"
  
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_endpoint" {
  secret_id     = aws_secretsmanager_secret.db_endpoint.id
  secret_string = aws_db_instance.main.address
}

# Redis Password
resource "random_password" "redis_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "redis_password" {
  name        = "${var.project_name}-redis-password"
  description = "Redis password for ${var.project_name}"
  
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis_password.result
}

resource "aws_db_instance" "main" {
  identifier           = "${var.project_name}-db"
  allocated_storage    = 20
  storage_type         = "gp3"
  engine               = "postgres"
  engine_version       = "15"
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.db_username
  password             = random_password.db_password.result
  parameter_group_name = "default.postgres15"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = var.tags
}

output "db_instance_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  value = aws_db_instance.main.address
}

output "db_password_secret_arn" {
  value       = aws_secretsmanager_secret.db_password.arn
  description = "The ARN of the DB secret in Secrets Manager"
}

output "redis_password_secret_arn" {
  value       = aws_secretsmanager_secret.redis_password.arn
  description = "The ARN of the Redis secret in Secrets Manager"
}

# ECS Fargate service for API. ARM64 (Graviton) = 20% cheaper than x86.
#
# 🟡 IMPORTANT: right-size CPU + memory based on actual usage from CloudWatch.
# the source project was OVERSIZED at 4 vCPU / 8 GB (using 0.9% CPU) — wasted $150/mo.
# Start with 0.5 vCPU / 1 GB and scale up if needed.

# ECR repository
resource "aws_ecr_repository" "api" {
  name                 = "${local.name_prefix}-api"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lifecycle policy — keep last 10 images, expire untagged after 1 day
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["main", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${local.name_prefix}-api"
  retention_in_days = 30
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "ECS tasks — ingress from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── IAM ──
# Task execution role — pull image, fetch secrets at task launch, push logs
resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_default" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "secrets-read"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        # Scope to this project's 8 grouped secrets — matches secrets-migrate.sh.
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project}/${var.environment}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        # Scope KMS decrypt to the Aurora key we manage in aurora.tf.
        Resource = [aws_kms_key.aurora.arn]
      }
    ]
  })
}

# Task role — for runtime AWS calls from your app code (S3 read, etc.)
resource "aws_iam_role" "task" {
  name = "${local.name_prefix}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Allow ECS Exec
resource "aws_iam_role_policy" "task_ssm" {
  name = "ssm-exec"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# ── Task Definition ──
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # 🟡 RIGHT-SIZE THESE based on actual usage. Start small.
  cpu    = "512"  # 0.5 vCPU
  memory = "1024" # 1 GB

  runtime_platform {
    cpu_architecture        = "ARM64" # 20% cheaper. Switch to X86_64 if needed.
    operating_system_family = "LINUX"
  }

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true

      portMappings = [{
        containerPort = 3000
        protocol      = "tcp"
      }]

      environment = [
        { name = "NODE_ENV", value = var.environment },
        { name = "PORT", value = "3000" }
        # Add more non-secret env vars here
      ]

      secrets = [
        # Inject DATABASE_URL from Secrets Manager
        {
          name      = "DATABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.db.arn}:DATABASE_URL::"
        }
        # Add more secrets here, one per env var
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }

      # Container-level health check runs INSIDE the container, so it must use
      # a tool the image ships. Node images don't include wget; we use node
      # itself for portability. For non-Node runtimes, DELETE this healthCheck
      # block — the ALB target-group health check in alb.tf is enough on its own.
      healthCheck = {
        command = [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions] # allow CI to update image
  }
}

# ── Service ──
resource "aws_ecs_service" "api" {
  name            = "${local.name_prefix}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "app"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = 120 # allow boot time

  lifecycle {
    ignore_changes = [task_definition, desired_count] # CI manages these
  }

  depends_on = [aws_lb_listener.api_https]
}

output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "ecs_service_name" { value = aws_ecs_service.api.name }
output "ecr_repo_uri" { value = aws_ecr_repository.api.repository_url }

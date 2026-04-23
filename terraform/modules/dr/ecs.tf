############################################################
# ECS Fargate - 5 services, desired_count = 0 by default.
# Auto-scaling is wired so they can scale 0 -> N on failover.
############################################################

# ----------------------------------------------------------
# Cluster
# ----------------------------------------------------------

resource "aws_ecs_cluster" "dr" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster", Module = "dr" })
}

resource "aws_ecs_cluster_capacity_providers" "dr" {
  cluster_name       = aws_ecs_cluster.dr.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ----------------------------------------------------------
# Log groups (one per service)
# ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs" {
  for_each = var.services

  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = 7
  tags              = var.tags
}

# ----------------------------------------------------------
# Execution role - pulls images and writes logs
# ----------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read the DR secrets
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      var.db_secret_arn,
      var.redis_secret_arn,
      var.cognito_secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${var.name_prefix}-ecs-exec-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# ----------------------------------------------------------
# Task role - per service (minimal). For this DR deploy we use a
# shared task role; tighten per service later.
# ----------------------------------------------------------

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "task" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      var.db_secret_arn,
      var.redis_secret_arn,
      var.cognito_secret_arn,
    ]
  }

  statement {
    actions   = ["events:PutEvents"]
    resources = ["arn:aws:events:${var.region}:${var.account_id}:event-bus/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "${var.name_prefix}-ecs-task"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ----------------------------------------------------------
# Target groups (one per service) + listener rules
# ----------------------------------------------------------

resource "aws_lb_target_group" "svc" {
  for_each = var.services

  name        = "${var.name_prefix}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(var.tags, { Service = each.key, Module = "dr" })
}

locals {
  # Listener rule priorities spread across services.
  priority_index = {
    for idx, svc in sort(keys(var.services)) : svc => 100 + idx * 10
  }
}

resource "aws_lb_listener_rule" "svc" {
  for_each = var.enable_https_listener ? var.services : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = local.priority_index[each.key]

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/api/${each.key}*"]
    }
  }

  tags = merge(var.tags, { Service = each.key })
}

# ----------------------------------------------------------
# Task definitions (one per service)
# ----------------------------------------------------------

resource "aws_ecs_task_definition" "svc" {
  for_each = var.services

  family                   = "${var.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${each.value.image}"
    essential = true

    portMappings = [{
      containerPort = each.value.port
      protocol      = "tcp"
    }]

    environment = [
      { name = "LOG_LEVEL", value = "info" },
      { name = "AWS_REGION", value = var.region },
      { name = "REGION_ROLE", value = "dr" },
    ]

    secrets = [
      { name = "DB_HOST", valueFrom = "${var.db_secret_arn}:host::" },
      { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      { name = "REDIS_HOST", valueFrom = "${var.redis_secret_arn}:endpoint::" },
      { name = "REDIS_AUTH", valueFrom = "${var.redis_secret_arn}:auth_token::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:${each.value.port}/healthz || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
  }])

  tags = merge(var.tags, { Service = each.key, Module = "dr" })
}

# ----------------------------------------------------------
# Services - desired_count = 0 by default (scales from zero)
# ----------------------------------------------------------

resource "aws_ecs_service" "svc" {
  for_each = var.services

  name            = each.key
  cluster         = aws_ecs_cluster.dr.id
  task_definition = aws_ecs_task_definition.svc[each.key].arn
  desired_count   = 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.eks_nodes_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.enable_https_listener ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.svc[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(var.tags, { Service = each.key, Module = "dr" })
}

# ----------------------------------------------------------
# Autoscaling (ready to scale up on failover)
# ----------------------------------------------------------

resource "aws_appautoscaling_target" "svc" {
  for_each = var.services

  max_capacity       = 4
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.dr.name}/${aws_ecs_service.svc[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "svc_cpu" {
  for_each = var.services

  name               = "${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

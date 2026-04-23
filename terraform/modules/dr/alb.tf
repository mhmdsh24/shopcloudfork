############################################################
# DR public ALB — pre-provisioned so Route 53 failover records
# always have a target, even while ECS services are at 0 tasks.
############################################################

resource "aws_lb" "public" {
  name               = "${var.name_prefix}-public-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.public_alb_sg_id]

  idle_timeout               = 60
  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-public-alb", Module = "dr" })
}

# Plain HTTP listener that redirects to HTTPS.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener that returns 503 by default — real rules are
# added per service below.
resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "ShopCloud DR: no route"
      status_code  = "503"
    }
  }
}

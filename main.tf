terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configures persistent state tracking inside a unique state bucket for the weather application
  backend "s3" {
    bucket = "weather-prediction-tfstate-017562255734"
    key    = "production/weather-app/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = "eu-north-1"
}

# =================================================================
# 0. VARIABLES & DATA DISCOVERY LAYER (SMART DETECTION)
# =================================================================

variable "root_domain_name" {
  type        = string
  description = "The raw root domain name hosted inside your Route 53 account (e.g., example.com)"
}

variable "app_subdomain_name" {
  type        = string
  description = "The full custom address where the app will be accessed (e.g., ://example.com)"
}

variable "weather_api_key" {
  type        = string
  description = "The secret WeatherAPI token used to pull forecast data maps"
  sensitive   = true
}

# Dynamic Discovery: Look for an existing VPC from Project 1 using Name tags
data "aws_vpcs" "existing" {
  tags = { Name = "crypto-production-vpc" }
}

# Dynamic Discovery: Look for an existing public ALB from Project 1 using its explicit name
data "aws_lb" "existing" {
  name = "crypto-app-alb"
}

locals {
  # Calculate if we need to provision a new network baseline from scratch
  create_network = length(data.aws_vpcs.existing.ids) == 0 ? 1 : 0
  
  # Resolve which network assets to lock onto dynamically
  vpc_id     = local.create_network == 1 ? (length(aws_vpc.weather_vpc) > 0 ? aws_vpc.weather_vpc[0].id : "") : tolist(data.aws_vpcs.existing.ids)[0]
  subnet_a   = local.create_network == 1 ? (length(aws_subnet.public_a) > 0 ? aws_subnet.public_a[0].id : "") : tolist(data.aws_subnets.vpc_subnets.ids)[0]
  subnet_b   = local.create_network == 1 ? (length(aws_subnet.public_b) > 0 ? aws_subnet.public_b[0].id : "") : tolist(data.aws_subnets.vpc_subnets.ids)[1]
}

# Look up subnets automatically if using the pre-existing VPC mapping layer
data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# =================================================================
# 1. CONDITIONAL NETWORK PROVISIONING (Fires ONLY if Project 1 is missing)
# =================================================================

resource "aws_vpc" "weather_vpc" {
  count                = local.create_network
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "weather-production-vpc" }
}

resource "aws_internet_gateway" "igw" {
  count  = local.create_network
  vpc_id = aws_vpc.weather_vpc[0].id
}

resource "aws_subnet" "public_a" {
  count                   = local.create_network
  vpc_id                  = aws_vpc.weather_vpc[0].id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  count                   = local.create_network
  vpc_id                  = aws_vpc.weather_vpc[0].id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "eu-north-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public_rt" {
  count  = local.create_network
  vpc_id = aws_vpc.weather_vpc[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
}

resource "aws_route_table_association" "pub_assoc_a" {
  count          = local.create_network
  subnet_id      = aws_subnet.public_a[0].id
  route_table_id = aws_route_table.public_rt[0].id
}

resource "aws_route_table_association" "pub_assoc_b" {
  count          = local.create_network
  subnet_id      = aws_subnet.public_b[0].id
  route_table_id = aws_route_table.public_rt[0].id
}

# =================================================================
# 2. SECURITY POLICY CONTROLS (FIREWALL SHIELDS)
# =================================================================

# ALB Security Group: Created ONLY if running completely standalone without Project 1
resource "aws_security_group" "alb_sg" {
  count  = local.create_network
  name   = "crypto-alb-sg" 
  vpc_id = local.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Weather Task Security Group: Created irrespective to encapsulate your application containers
resource "aws_security_group" "ecs_tasks_sg" {
  name   = "weather-ecs-tasks-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Opens outbound paths so your container can pull forecast metrics from ://weatherapi.com
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =================================================================
# 3. STORAGE REGISTRY & MANAGEMENT RUNTIME
# =================================================================

resource "aws_ecr_repository" "app_ecr" {
  name                 = "weather-prediction-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecs_cluster" "main" {
  name = "weather-production-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "weather-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "://amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/weather-prediction-app"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "app" {
  family                   = "weather-prediction-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "weather-app"
    image     = "${aws_ecr_repository.app_ecr.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 5000
      hostPort      = 5000
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = "eu-north-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
    environment = [
      { name = "WEATHER_API_KEY", value = var.weather_api_key }
    ]
  }])
}

# =================================================================
# 4. ROUTING LOGIC & CO-SHARING ALBS
# =================================================================

# ALB: Created ONLY if running completely standalone
resource "aws_alb" "main" {
  count           = local.create_network
  name            = "crypto-app-alb"
  subnets         = [aws_subnet.public_a[0].id, aws_subnet.public_b[0].id]
  security_groups = [aws_security_group.alb_sg[0].id]
}

resource "aws_alb_target_group" "app" {
  name        = "weather-app-target-group"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

# Standalone basic listeners (Created ONLY if working on an isolated account setup)
resource "aws_alb_listener" "http" {
  count             = local.create_network
  load_balancer_arn = aws_alb.main[0].arn
  port              = "80"
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

resource "aws_alb_listener" "https" {
  count             = local.create_network
  load_balancer_arn = aws_alb.main[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.app_cert_verify.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app.arn
  }
}

# SMART ROUTING STEP: If Project 1's ALB exists, discover its Port 443 Listener
data "aws_lb_listener" "crypto_https" {
  count             = local.create_network == 1 ? 0 : 1
  load_balancer_arn = data.aws_lb.existing.arn
  port              = 443
}

# Dynamic Listener Rule: Appends a Host-header condition right onto Project 1's ALB
resource "aws_lb_listener_rule" "weather_rule" {
  count        = local.create_network == 1 ? 0 : 1
  listener_arn = data.aws_lb_listener.crypto_https[0].arn
  priority     = 20 

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app.arn
  }

  condition {
    host_header {
      values = [var.app_subdomain_name]
    }
  }
}

# =================================================================
# 5. RUNNING THE CONTAINER SERVICE
# =================================================================

resource "aws_ecs_service" "main" {
  name            = "weather-prediction-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    subnets          = [local.subnet_a, local.subnet_b]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.arn
    container_name   = "weather-app"
    container_port   = 5000
  }
}

# =================================================================
# 6. ROUTE 53 AUTOMATION & DOMAIN SSL VALIDATION
# =================================================================

data "aws_route53_zone" "primary" {
  name         = "${var.root_domain_name}."
  private_zone = false
}

resource "aws_acm_certificate" "app_cert" {
  domain_name       = var.app_subdomain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  count = 1

  allow_overwrite = true
  name            = tolist(aws_acm_certificate.app_cert.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.app_cert.domain_validation_options)[0].resource_record_value]
  ttl             = 60
  type            = tolist(aws_acm_certificate.app_cert.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.primary.zone_id
}

resource "aws_acm_certificate_validation" "app_cert_verify" {
  certificate_arn         = aws_acm_certificate.app_cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}

resource "aws_route53_record" "app_alias" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.app_subdomain_name
  type    = "A"
  alias {
    name                   = local.create_network == 1 ? aws_alb.main.dns_name : data.aws_lb.existing.dns_name
    zone_id                = local.create_network == 1 ? aws_alb.main.zone_id : data.aws_lb.existing.zone_id
    evaluate_target_health = true
  }
}

# =================================================================
# 7. OUTPUTS
# =================================================================

output "custom_domain_url" {
  value       = "https://${var.app_subdomain_name}"
  description = "Your live weather forecasting endpoint link"
}

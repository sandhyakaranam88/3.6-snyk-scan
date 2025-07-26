provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "upload" {
  name = "service-upload"
}
resource "aws_ecr_repository" "queue" {
  name = "service-queue"
}

resource "aws_s3_bucket" "upload_bucket" {
  bucket = "${var.prefix}-upload-bucket"
  force_destroy = true
}

resource "aws_sqs_queue" "message_queue" {
  name = "${var.prefix}-message-queue"
}

resource "aws_iam_role" "task_exec" {
  name = "${var.prefix}-exec-role"
  assume_role_policy = jsonencode({
    Version="2012-10-17",
    Statement=[{Effect="Allow",Principal={Service="ecs-tasks.amazonaws.com"},Action="sts:AssumeRole"}]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

resource "aws_iam_role_policy" "app_permissions" {
  name = "${var.prefix}-app-policy"
  role = aws_iam_role.task_exec.id
  policy = jsonencode({
    Version="2012-10-17",
    Statement=[
      {Effect="Allow",Action=["s3:PutObject","s3:GetObject"],Resource="*"},
      {Effect="Allow",Action=["sqs:SendMessage"],Resource=aws_sqs_queue.message_queue.arn}
    ]
  })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.prefix}-cluster"
}

resource "aws_ecs_task_definition" "upload" {
  family                   = "${var.prefix}-upload-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec.arn
  container_definitions    = jsonencode([{
    name      = "upload"
    image     = "${aws_ecr_repository.upload.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{containerPort=5000,hostPort=5000}]
    environment = [
      {name="BUCKET", value=aws_s3_bucket.upload_bucket.bucket},
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = "/ecs/${var.prefix}-upload"
        "awslogs-region" = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "upload" {
  name            = "${var.prefix}-upload-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.upload.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = []
    assign_public_ip = true
  }
}

# Repeat task_definition and service for queue...
resource "aws_ecs_task_definition" "queue" {
  family = "${var.prefix}-queue-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                   = "256"
  memory                = "512"
  execution_role_arn    = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([{
    name="queue"; image="${aws_ecr_repository.queue.repository_url}:${var.image_tag}"
    essential=true; portMappings=[{containerPort=5001,hostPort=5001}]
    environment=[{name="QUEUE_URL", value=aws_sqs_queue.message_queue.id}]
    logConfiguration={
      logDriver="awslogs"; options={
        "awslogs-group"="/ecs/${var.prefix}-queue"; "awslogs-region"=var.aws_region; "awslogs-stream-prefix"="ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "queue" {
  name="${var.prefix}-queue-service";
  cluster=aws_ecs_cluster.this.id;
  task_definition=aws_ecs_task_definition.queue.arn;
  desired_count=1; launch_type="FARGATE";
  network_configuration {
    subnets=data.aws_subnets.default.ids
    security_groups=[]
    assign_public_ip=true
  }
}

data "aws_subnets" "default" {
  filter { name="default-for-az"; values=["true"] }
}

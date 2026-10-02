terraform {
  backend "s3" {
    bucket       = "dhiren9939-state-bucket"
    key          = "projects/mint-loadgen.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.39.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "debian" {
  name = "/aws/service/debian/release/12/latest/amd64"
}

resource "aws_key_pair" "loadgen" {
  key_name   = "mint-loadgen-key"
  public_key = var.ssh_public_key
}

resource "aws_iam_role" "loadgen" {
  name = "mint-loadgen-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.loadgen.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# after.sh reads the run's metrics from CloudWatch on this box
resource "aws_iam_role_policy" "read_metrics" {
  name = "mint-loadgen-read-metrics"
  role = aws_iam_role.loadgen.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:GetMetricData", "cloudwatch:ListMetrics"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "loadgen" {
  name = "mint-loadgen-profile"
  role = aws_iam_role.loadgen.name
}

resource "aws_security_group" "loadgen" {
  name        = "mint-loadgen-sg"
  description = "SSH in, everything out for the load generator"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.loadgen.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ssh_cidr
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.loadgen.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "loadgen" {
  ami                         = data.aws_ssm_parameter.debian.value
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.loadgen.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.loadgen.id]
  iam_instance_profile        = aws_iam_instance_profile.loadgen.name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/user_data.sh")

  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "mint-loadgen"
  }
}

# bench-ecs: reseed.sh empties and fills the table from this box
resource "aws_iam_role_policy" "seed_table" {
  count = var.bench_table_arn == null ? 0 : 1

  name = "mint-loadgen-seed-table"
  role = aws_iam_role.loadgen.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:DescribeTable", "dynamodb:Scan", "dynamodb:BatchWriteItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      Resource = var.bench_table_arn
    }]
  })
}

# bench-ecs: reseed.sh puts the service back to its minimum task count and waits for it
resource "aws_iam_role_policy" "reset_service" {
  count = var.bench_ecs_service_arn == null ? 0 : 1

  name = "mint-loadgen-reset-service"
  role = aws_iam_role.loadgen.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
      Resource = var.bench_ecs_service_arn
    }]
  })
}

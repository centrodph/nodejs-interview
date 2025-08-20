###############################################
# Terraform - Single-file sample AWS infra:
# - VPC (public/private subnets)
# - Elastic Beanstalk (LoadBalanced, EC2-backed)
# - RDS PostgreSQL in private subnets
# This file is intentionally verbose and documented.
###############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

###############################################
# Provider configuration
###############################################
provider "aws" {
  region = var.aws_region
}

###############################################
# Variables (provide via terraform.tfvars or CLI)
###############################################
variable "aws_region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project prefix used for naming resources."
  type        = string
  default     = "sample-eb-rds"
}

variable "ec2_key_pair_name" {
  description = "Existing EC2 key pair name for SSH access to EB instances."
  type        = string
}

variable "eb_instance_type" {
  description = "Instance type for Elastic Beanstalk EC2 instances."
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for PostgreSQL."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master password for PostgreSQL."
  type        = string
  sensitive   = true
}

###############################################
# Locals (naming and tagging)
###############################################
locals {
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Environment = "dev"
  }

  # Compact name glue for resources
  name_prefix = var.project_name
}

###############################################
# Networking: VPC, Subnets, Routes, IGW
###############################################
resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public subnets egress
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnets (two AZs)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-a"
    Tier = "public"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-b"
    Tier = "public"
  })
}

# Private subnets (for RDS)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-a"
    Tier = "private"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-b"
    Tier = "private"
  })
}

# Route table and routes for public subnets to reach the Internet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private route table (no NAT for sample; RDS does not need Internet egress)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private_a_assoc" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b_assoc" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# Availability zones data source
data "aws_availability_zones" "available" {
  state = "available"
}

###############################################
# Security Groups
###############################################

# ALB / EB Load Balancer security group (ingress 80/443 from Internet)
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP/HTTPS from Internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# EB EC2 instances security group (allow HTTP only from ALB)
resource "aws_security_group" "eb_ec2" {
  name        = "${local.name_prefix}-eb-ec2-sg"
  description = "Allow HTTP from ALB to EB instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All egress from instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eb-ec2-sg"
  })
}

# RDS security group (allow Postgres only from EB EC2 SG)
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL from EB instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EB EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eb_ec2.id]
  }

  egress {
    description = "All egress from RDS (default)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

###############################################
# RDS: Subnet group and PostgreSQL instance
###############################################
resource "aws_db_subnet_group" "rds" {
  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-subnets"
  })
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-postgres"
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false
  storage_encrypted      = true
  backup_retention_period = 7
  deletion_protection    = false
  skip_final_snapshot    = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres"
  })
}

###############################################
# IAM: Roles for Elastic Beanstalk
###############################################

# Trust policy for EC2 instance role
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# EC2 instance role (used by EB instances)
resource "aws_iam_role" "eb_ec2_role" {
  name               = "${local.name_prefix}-eb-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = local.common_tags
}

# Attach standard web tier and SSM policies to EB EC2 role
resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_multicontainer" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile that EB uses for its EC2 instances
resource "aws_iam_instance_profile" "eb_instance_profile" {
  name = "${local.name_prefix}-eb-ec2-instance-profile"
  role = aws_iam_role.eb_ec2_role.name
}

# Trust policy for EB service role
data "aws_iam_policy_document" "eb_service_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["elasticbeanstalk.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# EB service role for enhanced health, managed updates, etc.
resource "aws_iam_role" "eb_service_role" {
  name               = "${local.name_prefix}-eb-service-role"
  assume_role_policy = data.aws_iam_policy_document.eb_service_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eb_service" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
}

resource "aws_iam_role_policy_attachment" "eb_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

###############################################
# Elastic Beanstalk: Application and Environment
###############################################

# EB application container
resource "aws_elastic_beanstalk_application" "app" {
  name        = "${local.name_prefix}-app"
  description = "Sample Elastic Beanstalk application"

  tags = local.common_tags
}

# EB environment (LoadBalanced, ALB). Uses Sample Application by default.
resource "aws_elastic_beanstalk_environment" "env" {
  name                = "${local.name_prefix}-env"
  application         = aws_elastic_beanstalk_application.app.name

  # Choose a suitable solution stack/platform for your runtime
  # Example for Node.js 18 on Amazon Linux 2 (update as AWS evolves)
  solution_stack_name = "64bit Amazon Linux 2 v5.8.1 running Node.js 18"

  # Option settings configure VPC, ALB, instance profile, and app environment variables
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  # Service role for EB (enhanced health, etc.)
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  # VPC integration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }

  # Subnets for instances (public for simplicity so they can reach Internet via IGW)
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [aws_subnet.public_a.id, aws_subnet.public_b.id])
  }

  # Subnets for ALB
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", [aws_subnet.public_a.id, aws_subnet.public_b.id])
  }

  # Public IPs for instances (since they are in public subnets)
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  # Security group for EB instances
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_ec2.id
  }

  # Security group for ALB
  setting {
    namespace = "aws:elb:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.alb.id
  }

  # EC2 instance profile and size
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_instance_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = var.ec2_key_pair_name
  }

  # Application environment variables for DB connectivity
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DATABASE_HOST"
    value     = aws_db_instance.postgres.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DATABASE_PORT"
    value     = "5432"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DATABASE_NAME"
    value     = var.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DATABASE_USER"
    value     = var.db_username
  }

  # Do NOT pass plaintext DB password to EB unless you have a secure need.
  # Prefer fetching it from Secrets Manager or SSM Parameter Store.
  # This sample omits DATABASE_PASSWORD on purpose.

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eb_service,
    aws_iam_role_policy_attachment.eb_enhanced_health
  ]
}

###############################################
# Outputs
###############################################
output "elastic_beanstalk_environment_url" {
  description = "CNAME URL for the Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.env.cname
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (hostname)."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "vpc_id" {
  description = "VPC ID for the provisioned network."
  value       = aws_vpc.main.id
}
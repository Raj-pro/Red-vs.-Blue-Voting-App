terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Latest Ubuntu 22.04 LTS AMI ─────────────────────────────────────────────
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── AZ data for managed subnet creation ──────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── Managed network (created only when IDs are not provided) ────────────────
resource "aws_vpc" "workshop" {
  count                = var.vpc_id == "" ? 1 : 0
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_subnet" "workshop" {
  count                   = var.subnet_id == "" ? 1 : 0
  vpc_id                  = var.vpc_id != "" ? var.vpc_id : aws_vpc.workshop[0].id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

resource "aws_internet_gateway" "workshop" {
  count  = var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.workshop[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_route_table" "workshop_public" {
  count  = var.vpc_id == "" ? 1 : 0
  vpc_id = aws_vpc.workshop[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.workshop[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "workshop_public" {
  count          = var.vpc_id == "" && var.subnet_id == "" ? 1 : 0
  subnet_id      = aws_subnet.workshop[0].id
  route_table_id = aws_route_table.workshop_public[0].id
}

locals {
  vpc_id    = var.vpc_id != "" ? var.vpc_id : aws_vpc.workshop[0].id
  subnet_id = var.subnet_id != "" ? var.subnet_id : aws_subnet.workshop[0].id

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Workshop    = "cloudvibe-k8s"
  }
}

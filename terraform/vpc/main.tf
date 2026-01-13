terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "eks-project-terraform-state-025988852505"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    {
      Name        = "${var.project_name}-vpc"
      Environment = var.environment
    },
    var.tags
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      Name        = "${var.project_name}-igw"
      Environment = var.environment
    },
    var.tags
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name        = "${var.project_name}-public-${count.index + 1}"
      Environment = var.environment
      Type        = "Public"
    },
    var.tags
  )
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    {
      Name        = "${var.project_name}-private-${count.index + 1}"
      Environment = var.environment
      Type        = "Private"
    },
    var.tags
  )
}

# NAT Gateways
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(
    {
      Name        = "${var.project_name}-eip-${count.index + 1}"
      Environment = var.environment
    },
    var.tags
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    {
      Name        = "${var.project_name}-nat-${count.index + 1}"
      Environment = var.environment
    },
    var.tags
  )

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      Name        = "${var.project_name}-rt-public"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      Name        = "${var.project_name}-rt-private-${count.index + 1}"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_route" "private_nat" {
  count = length(var.private_subnet_cidrs)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPC Endpoints for EKS
resource "aws_vpc_endpoint" "ec2_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  security_group_ids = [aws_security_group.vpc_endpoint.id]

  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    {
      Name        = "${var.project_name}-ec2-endpoint"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_vpc_endpoint" "eks_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.eks"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  security_group_ids = [aws_security_group.vpc_endpoint.id]

  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    {
      Name        = "${var.project_name}-eks-endpoint"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name        = "${var.project_name}-vpc-endpoint-sg"
      Environment = var.environment
    },
    var.tags
  )
}

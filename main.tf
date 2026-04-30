provider "aws" {
  region = "ap-northeast-1"
}

terraform {
  backend "s3" {
    bucket       = "ryo-terraform-state-20260430"
    key          = "study-aws/terraform.tfstate"
    region       = "ap-northeast-1"
    profile      = "AdministratorAccess-058898200941"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# -------------------------
# SSH Key Pair
# -------------------------
resource "tls_private_key" "ryo_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ryo_private_key" {
  filename        = "${path.module}/ryo-key.pem"
  content         = tls_private_key.ryo_key.private_key_pem
  file_permission = "0400"
}

resource "aws_key_pair" "ryo_key" {
  key_name   = "ryo-key-terraform"
  public_key = tls_private_key.ryo_key.public_key_openssh

  tags = {
    Name = "ryo-key-terraform"
  }
}

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ryo-vpc"
  }
}

# -------------------------
# Public Subnet
# -------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "ryo-public-subnet"
  }
}

# -------------------------
# Internet Gateway
# -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ryo-igw"
  }
}

# -------------------------
# Route Table
# -------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ryo-public-rt"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------
# Security Group
# -------------------------
resource "aws_security_group" "web_sg" {
  name   = "ryo-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------
# EC2 (WordPress + MySQL)
# -------------------------
resource "aws_instance" "web" {
  ami                         = "ami-0d52744d6551d851e"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ryo_key.key_name

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  user_data_replace_on_change = true

  user_data = <<-EOF
#!/bin/bash
set -eux

apt-get update -y
apt-get install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

mkdir -p /home/ubuntu/wordpress
cd /home/ubuntu/wordpress

cat > docker-compose.yml <<EOL
services:
  db:
    image: mysql:8.0
    container_name: wordpress-db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${var.mysql_root_password}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: ${var.mysql_user}
      MYSQL_PASSWORD: ${var.mysql_password}
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    container_name: wordpress-app
    restart: always
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${var.mysql_user}
      WORDPRESS_DB_PASSWORD: ${var.mysql_password}
      WORDPRESS_DB_NAME: wordpress
    depends_on:
      - db

volumes:
  db_data:
EOL

chown -R ubuntu:ubuntu /home/ubuntu/wordpress
docker-compose up -d
EOF

  tags = {
    Name = "ryo-ec2"
  }
}

# -------------------------
# Elastic IP
# -------------------------
resource "aws_eip" "web_eip" {
  instance = aws_instance.web.id
}
# -------------------------------------------------------
# main.tf
# Windows Spot EC2 Instance with dynamic latest AMI
# -------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote backend – S3 bucket created by your existing script
  backend "s3" {
    bucket         = var.tf_state_bucket
    key            = "terraform-ansible-cicd/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -------------------------------------------------------
# Data Sources
# -------------------------------------------------------

# Always fetch the latest Windows Server 2022 Base AMI
data "aws_ami" "windows_latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Use default VPC for simplicity
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -------------------------------------------------------
# Security Group
# -------------------------------------------------------

resource "aws_security_group" "windows_sg" {
  name        = "${var.project_name}-windows-sg"
  description = "Security group for Windows EC2 - WinRM + RDP"
  vpc_id      = data.aws_vpc.default.id

  depends_on = [data.aws_vpc.default]

  # WinRM HTTP (Ansible uses this)
  ingress {
    description = "WinRM HTTP"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WinRM HTTPS
  ingress {
    description = "WinRM HTTPS"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RDP for manual access
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-windows-sg"
  })
}

# -------------------------------------------------------
# IAM Instance Profile (for SSM / future use)
# -------------------------------------------------------

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

  depends_on = [aws_iam_role.ec2_role]
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  depends_on = [aws_iam_role.ec2_role]
}

# -------------------------------------------------------
# Windows Spot EC2 Instance
# -------------------------------------------------------

resource "aws_spot_instance_request" "windows" {
  ami                  = data.aws_ami.windows_latest.id
  instance_type        = var.instance_type
  key_name             = var.key_name
  subnet_id            = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.windows_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Spot instance settings
  spot_type                      = "one-time"
  wait_for_fulfillment           = true
  instance_interruption_behavior = "terminate"

  # User data – enable WinRM so Ansible can connect
  user_data = base64encode(templatefile("${path.module}/userdata.ps1", {
    ansible_password = var.ansible_windows_password
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-windows-spot"
    Managed = "Terraform"
  })

  # Tag the underlying instance as well
  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_policy,
    aws_iam_instance_profile.ec2_profile,
  ]
}

# Tag the underlying instance (spot requests create the instance separately)
resource "aws_ec2_tag" "windows_instance_name" {
  resource_id = aws_spot_instance_request.windows.spot_instance_id
  key         = "Name"
  value       = "${var.project_name}-windows-spot"

  depends_on = [aws_spot_instance_request.windows]
}

# -------------------------------------------------------
# variables.tf
# -------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1" # Sydney – change to your region
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "terraform-ansible-demo"
}

variable "instance_type" {
  description = "EC2 instance type (must support Windows)"
  type        = string
  default     = "t3.micro" # Minimum recommended for Windows
}

variable "key_name" {
  description = "Name of existing EC2 Key Pair for RDP/WinRM"
  type        = string
  # Provided via GitHub Actions secret TF_VAR_key_name
}

variable "ansible_windows_password" {
  description = "Local admin password set on the Windows instance for Ansible WinRM"
  type        = string
  sensitive   = true
  # Provided via GitHub Actions secret TF_VAR_ansible_windows_password
}

variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
  # Provided via GitHub Actions secret TF_VAR_tf_state_bucket
  
}


variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "terraform-ansible-demo"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = "Balraj"
  }
}

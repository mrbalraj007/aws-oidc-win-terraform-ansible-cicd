# -------------------------------------------------------
# outputs.tf
# -------------------------------------------------------

output "spot_request_id" {
  description = "Spot instance request ID"
  value       = aws_spot_instance_request.windows.id
}

output "windows_instance_id" {
  description = "The underlying EC2 instance ID (fulfilled spot)"
  value       = aws_spot_instance_request.windows.spot_instance_id
}

output "windows_public_ip" {
  description = "Public IP of the Windows instance"
  value       = aws_spot_instance_request.windows.public_ip
}

output "windows_public_dns" {
  description = "Public DNS of the Windows instance"
  value       = aws_spot_instance_request.windows.public_dns
}

output "ami_id_used" {
  description = "The latest Windows AMI ID that was used"
  value       = data.aws_ami.windows_latest.id
}

output "ami_name_used" {
  description = "The AMI name that was used"
  value       = data.aws_ami.windows_latest.name
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.windows_sg.id
}

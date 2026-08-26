output "efs_file_system_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.jira_dc_efs.id
}

output "efs_file_system_dns_name" {
  description = "The DNS name of the EFS file system"
  value       = aws_efs_file_system.jira_dc_efs.dns_name
}

output "efs_file_system_arn" {
  description = "The ARN of the EFS file system"
  value       = aws_efs_file_system.jira_dc_efs.arn
}

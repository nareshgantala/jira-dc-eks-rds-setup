output "rds_security_group_id" {
  value = aws_security_group.rds_sg.id
}

output "efs_security_group_id" {
  description = "Security group ID for EFS mount targets"
  value       = aws_security_group.efs_sg.id
}

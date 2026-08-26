output "private_subnet_ids" {
  value = aws_subnet.private_subnet[*].id
}

output "jira_dc_db_subnet_group_id" {
  value = aws_db_subnet_group.jira_dc_db_subnet_group.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

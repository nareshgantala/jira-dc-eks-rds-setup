output "rds_cluster_endpoint" {
  description = "The database cluster writer endpoint"
  value       = aws_rds_cluster.jira_dc_rds_cluster.endpoint
}

output "rds_cluster_port" {
  description = "The database port"
  value       = aws_rds_cluster.jira_dc_rds_cluster.port
}

output "rds_database_name" {
  description = "The database name"
  value       = aws_rds_cluster.jira_dc_rds_cluster.database_name
}

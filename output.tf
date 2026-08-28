output "cluster_name" {
  description = "The EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl to connect to the EKS cluster"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}

output "rds_cluster_endpoint" {
  description = "The RDS PostgreSQL writer endpoint for Jira database connection"
  value       = module.rds.rds_cluster_endpoint
}

output "rds_cluster_port" {
  description = "The RDS PostgreSQL port"
  value       = module.rds.rds_cluster_port
}

output "rds_database_name" {
  description = "The Jira database name"
  value       = module.rds.rds_database_name
}

output "rds_master_user_secret_arn" {
  description = "The AWS Secrets Manager ARN storing the RDS master password"
  value       = module.rds.rds_master_user_secret_arn
}

output "efs_file_system_id" {
  description = "The EFS File System ID for Jira shared home storage"
  value       = module.efs.efs_file_system_id
}

output "efs_file_system_dns_name" {
  description = "The EFS File System DNS name"
  value       = module.efs.efs_file_system_dns_name
}

output "oidc_provider_url" {
  description = "The URL of the OIDC Provider without https:// prefix"
  value       = module.oidc.oidc_provider_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.oidc.oidc_provider_arn
}

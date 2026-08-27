output "oidc_url" {
  value = aws_eks_cluster.jira_dc_cluster.identity[0].oidc[0].issuer
}

output "cluster_endpoint" {
  value = aws_eks_cluster.jira_dc_cluster.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.jira_dc_cluster.certificate_authority[0].data
}

output "cluster_name" {
  value = aws_eks_cluster.jira_dc_cluster.name
}

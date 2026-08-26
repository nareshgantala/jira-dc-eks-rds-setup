output "oidc_url" {
  value = aws_eks_cluster.jira_dc_cluster.identity[0].oidc[0].issuer
}

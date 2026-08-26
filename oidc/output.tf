output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "The URL of the OIDC Provider without https:// prefix"
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

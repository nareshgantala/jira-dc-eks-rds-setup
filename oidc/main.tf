# 1. Ask Terraform to read the SSL certificate from your EKS cluster's OIDC URL
data "tls_certificate" "eks" {
  url = var.oidc_url
}

# 2. Register that OIDC provider with AWS IAM
resource "aws_iam_openid_connect_provider" "eks" {
  # The unique OIDC URL of your EKS cluster
  url = var.oidc_url

  # The audience is always AWS STS
  client_id_list = ["sts.amazonaws.com"]

  # The SSL thumbprint fetched automatically by the data source above
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.project}-${var.env}-eks-oidc"
  }
}

resource "aws_eks_cluster" "jira_dc_cluster" {
  name = "${var-project}-${var.env}-eks-cluster"

  access_config {
    authentication_mode = "API"
  }

  role_arn = var.eks_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-attach,
  ]
}

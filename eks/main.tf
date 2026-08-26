resource "aws_eks_cluster" "jira_dc_cluster" {
  name = "${var.project}-${var.env}-eks-cluster"

  access_config {
    authentication_mode = "API"
  }

  role_arn = var.eks_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids
  }
}


resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.jira_dc_cluster.name
  node_group_name = "example"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

}

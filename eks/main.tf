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
  instance_types  = var.instance_types
  disk_size       = var.disk_size

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

}

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "cluster_creator" {
  cluster_name  = aws_eks_cluster.jira_dc_cluster.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_creator" {
  cluster_name  = aws_eks_cluster.jira_dc_cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type = "cluster"
  }
}

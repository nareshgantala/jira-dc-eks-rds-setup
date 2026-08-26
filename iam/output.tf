output "eks_role_arn" {
  value = aws_iam_role.eks_role.arn
}

output "node_group_role_arn" {
  value = aws_iam_role.node_group_role.arn
}

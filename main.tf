module "vpc" {
  source  = "./vpc"
  project = var.project
  env     = var.env
}

module "iam" {
  source  = "./iam"
  project = var.project
  env     = var.env
}


module "eks" {
  source              = "./eks"
  project             = var.project
  env                 = var.env
  subnet_ids          = module.vpc.private_subnet_ids
  eks_role_arn        = module.iam.eks_role_arn
  node_group_role_arn = module.iam.node_group_role_arn
  depends_on = [
    module.iam,
    module.vpc
  ]
}

module "security" {
  source   = "./security"
  project  = var.project
  env      = var.env
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

module "rds" {
  source                     = "./rds"
  jira_dc_db_subnet_group_id = module.vpc.jira_dc_db_subnet_group_id
  rds_security_group_id      = module.security.rds_security_group_id
}


module "oidc" {
  source   = "./oidc"
  project  = var.project
  env      = var.env
  oidc_url = module.eks.oidc_url
}


module "efs" {
  source                = "./efs"
  project               = var.project
  env                   = var.env
  private_subnet_ids    = module.vpc.private_subnet_ids
  efs_security_group_id = module.security.efs_security_group_id
}



# 1. IAM Role with OIDC Trust Policy
resource "aws_iam_role" "ebs_csi_role" {
  name = "${var.project}-${var.env}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.oidc.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.oidc.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${module.oidc.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 2. Attach AWS Managed Policy for EBS CSI Driver
resource "aws_iam_role_policy_attachment" "ebs_csi_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_role.name
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = "${var.project}-${var.env}-eks-cluster"
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  # Ensures the node group is ready before installing the driver pods
  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.ebs_csi_policy_attach
  ]
}

# EFS CSI Driver - IAM Role with OIDC Trust Policy
resource "aws_iam_role" "efs_csi_role" {
  name = "${var.project}-${var.env}-efs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.oidc.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.oidc.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
            "${module.oidc.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_role.name
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name             = "${var.project}-${var.env}-eks-cluster"
  addon_name               = "aws-efs-csi-driver"
  service_account_role_arn = aws_iam_role.efs_csi_role.arn

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.efs_csi_policy_attach
  ]
}


# In main.tf — IAM Role for ALB Controller
resource "aws_iam_role" "alb_controller_role" {
  name = "${var.project}-${var.env}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.oidc.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.oidc.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${module.oidc.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# IAM Policy for AWS Load Balancer Controller
resource "aws_iam_policy" "alb_controller_policy" {
  name        = "${var.project}-${var.env}-alb-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/alb_iam_policy.json")
}

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "alb_controller_policy_attach" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = "${var.project}-${var.env}-eks-cluster"
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller_role.arn
        }
      }
    })
  ]

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.alb_controller_policy_attach
  ]
}

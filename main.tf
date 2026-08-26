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

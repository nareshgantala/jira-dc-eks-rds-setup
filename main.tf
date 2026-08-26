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



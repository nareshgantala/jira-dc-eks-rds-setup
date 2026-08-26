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

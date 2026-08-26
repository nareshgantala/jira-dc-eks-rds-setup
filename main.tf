module "vpc" {
  source  = "./vpc"
  project = var.project
  env     = var.env

}

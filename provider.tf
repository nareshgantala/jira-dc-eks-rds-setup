terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
  backend "s3" {}
}


# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Configure the Kubernetes Provider
# References module.eks outputs so these values are resolved after the cluster
# is created, avoiding the chicken-and-egg problem with data sources.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Configure the Helm Provider
# Note: In Helm provider v3+, the nested `kubernetes {}` block was removed.
# Helm automatically uses the kubernetes provider configuration.
provider "helm" {
}

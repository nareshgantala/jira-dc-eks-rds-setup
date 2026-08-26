variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "eks_role_arn" {
  type    = string
  default = ""
}


variable "node_group_role_arn" {
  type    = string
  default = ""
}

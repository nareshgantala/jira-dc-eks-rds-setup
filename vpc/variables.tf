variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "project" {
  type = string
}

variable "env" {
  type = string
}

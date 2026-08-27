variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "efs_security_group_id" {
  description = "Security group ID allowing NFS port 2049 traffic from worker nodes"
  type        = string
}

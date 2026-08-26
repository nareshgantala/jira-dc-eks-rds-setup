# RDS Security Group

resource "aws_security_group" "rds_sg" {
  name        = "${var.project}-${var.env}-rds-sg"
  description = "Allow traffic to rds"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-${var.env}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ingress_rds" {
  security_group_id = aws_security_group.rds_sg.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

resource "aws_vpc_security_group_egress_rule" "egress_rds" {
  security_group_id = aws_security_group.rds_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

#EFS Mount Security Group
resource "aws_security_group" "efs_sg" {
  name        = "${var.project}-${var.env}-efs-sg"
  description = "Allow traffic to efs"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-${var.env}-efs-sg"
  }
}


resource "aws_vpc_security_group_ingress_rule" "ingress_efs" {
  security_group_id = aws_security_group.efs_sg.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 2049
  ip_protocol       = "tcp"
  to_port           = 2049
}

resource "aws_vpc_security_group_egress_rule" "egress_efs" {
  security_group_id = aws_security_group.efs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

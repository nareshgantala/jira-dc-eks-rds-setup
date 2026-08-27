resource "aws_efs_file_system" "jira_dc_efs" {
  creation_token   = "jira-dc-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags = {
    Name = "${var.project}-${var.env}-efs"
  }
}

resource "aws_efs_mount_target" "jira_dc_efs_mount_target" {
  count           = 3
  file_system_id  = aws_efs_file_system.jira_dc_efs.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.efs_security_group_id]
}


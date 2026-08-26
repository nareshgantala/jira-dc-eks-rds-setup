resource "aws_rds_cluster" "jira_dc_rds_cluster" {
  cluster_identifier          = "jira-dc-rds-cluster"
  engine                      = "aurora-postgresql"
  engine_mode                 = "provisioned"
  engine_version              = "16.1"
  database_name               = "jiradb"
  master_username             = "postgres"
  db_subnet_group_name        = var.jira_dc_db_subnet_group_id
  vpc_security_group_ids      = [var.rds_security_group_id]
  storage_encrypted           = true
  manage_master_user_password = true
  skip_final_snapshot         = true

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "default" {
  cluster_identifier = aws_rds_cluster.jira_dc_rds_cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.jira_dc_rds_cluster.engine
}

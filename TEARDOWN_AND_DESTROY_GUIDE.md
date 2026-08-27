# Complete Lab Teardown & Destroy Guide (Zero Extra Cost Guarantee)

This guide provides the **exact step-by-step sequence** to safely tear down the entire Jira Data Center infrastructure on AWS EKS, ensuring that **zero dangling resources** remain and **no unnecessary AWS charges** are incurred.

---

## ⚠️ Critical Note: The Order Matters!

Jira Data Center runs dynamically created resources inside AWS that are **managed by Kubernetes controllers**, not by Terraform state:
1. **AWS Application Load Balancer (ALB)**: Provisioned dynamically by the AWS Load Balancer Controller in response to the Jira Ingress.
2. **AWS EBS gp3 Volume**: Provisioned dynamically by the EBS CSI Driver in response to the `local-home-jira-0` PVC.
3. **AWS EFS Access Point**: Provisioned dynamically by the EFS CSI Driver in response to the `jira-shared-home` PVC.

> [!CAUTION]
> **Do NOT run `terraform destroy` directly first!**
> If you run `terraform destroy` while the Jira Ingress and EBS volume still exist, AWS will reject the deletion of your VPC and subnets with a `DependencyViolation` error (because the ALB's Network Interfaces are still attached). This can leave orphaned resources running and costing money.

---

## The 4-Step Destruction Workflow

### Step 1: Uninstall Jira & Delete In-Cluster Storage

Run these commands in PowerShell (Windows) or Bash (macOS/Linux):

#### Windows PowerShell:
```powershell
# 1. Uninstall the Jira Helm chart
# (This tells the AWS Load Balancer Controller to delete the physical AWS Application Load Balancer!)
helm uninstall jira -n jira

# 2. Delete all PersistentVolumeClaims
# (This releases and deletes the physical AWS EBS gp2/gp3 volume in AWS)
kubectl delete pvc --all -n jira

# 3. Delete the Jira namespace
kubectl delete namespace jira
```

#### Linux / macOS (Bash):
```bash
helm uninstall jira -n jira
kubectl delete pvc --all -n jira
kubectl delete namespace jira
```

---

### Step 2: Wait for AWS ALB Deletion (~60-90 seconds)

After running `helm uninstall`, the AWS Load Balancer Controller requires 1 to 2 minutes to communicate with AWS ELBv2 APIs to deregister targets, delete listener rules, and delete the physical ALB.

Verify that the Jira load balancer is completely gone:

#### Windows PowerShell:
```powershell
# Should return no load balancers starting with 'k8s-jira'
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'jira')].LoadBalancerName" --output table
```

#### Linux / macOS (Bash):
```bash
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'jira')].LoadBalancerName" --output table
```

*Once the query returns empty or `None`, proceed to Step 3.*

---

### Step 3: Run `terraform destroy`

Now that all in-cluster AWS dependencies have been cleaned up, Terraform can cleanly and safely destroy all cloud resources in reverse dependency order:

#### Windows PowerShell & Bash:
```bash
terraform destroy -var-file="env/dev/terraform.tfvars"
```

When prompted:
```text
Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
```

#### What Terraform Will Destroy:
* ✅ `helm_release.alb_controller` (AWS Load Balancer Controller Helm chart)
* ✅ `kubernetes_storage_class_v1.efs_sc` (`efs-sc` StorageClass)
* ✅ `aws_eks_addon.efs_csi` & `aws_eks_addon.ebs_csi` (EKS Storage Drivers)
* ✅ `aws_eks_node_group.example` (EC2 `m5.xlarge` Worker Nodes)
* ✅ `aws_eks_cluster.jira_dc_cluster` (EKS Control Plane v1.31)
* ✅ `aws_rds_cluster_instance` & `aws_rds_cluster` (Aurora Serverless v2 PostgreSQL)
* ✅ `aws_efs_mount_target` (3x ENIs across AZs) & `aws_efs_file_system` (EFS volume)
* ✅ `aws_nat_gateway` & `aws_eip` (NAT Gateway & Elastic IP)
* ✅ `aws_route_table_association`, `aws_route_table`, `aws_subnet` (6 subnets)
* ✅ `aws_internet_gateway` & `aws_vpc`
* ✅ IAM Roles, Policies, Attachments, and OIDC Provider

---

### Step 4: Zero-Cost Sanity Verification (Check Remaining AWS Assets)

Run this verification block to guarantee that **no billable resources remain running in `us-east-1`**:

#### Windows PowerShell:
```powershell
Write-Host "=== 1. Checking Active Load Balancers ===" -ForegroundColor Cyan
aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName" --output table

Write-Host "=== 2. Checking Active NAT Gateways ===" -ForegroundColor Cyan
aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" --query "NatGateways[*].NatGatewayId" --output table

Write-Host "=== 3. Checking Active EKS Clusters ===" -ForegroundColor Cyan
aws eks list-clusters --query "clusters" --output table

Write-Host "=== 4. Checking Active RDS Clusters ===" -ForegroundColor Cyan
aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier" --output table

Write-Host "=== 5. Checking Active EFS Filesystems ===" -ForegroundColor Cyan
aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output table

Write-Host "=== 6. Checking Unattached Elastic IPs ===" -ForegroundColor Cyan
aws ec2 describe-addresses --query "Addresses[*].PublicIp" --output table
```

#### Expected Result:
Every single table should be empty (`None` or empty list). If all are empty, your AWS account is at **$0 / hour** for this project.

---

## Automated 1-Click Script (`destroy-lab.ps1`)

If you want an automated, hands-off script that runs this entire sequence on Windows, run the provided script from the repository root:

```powershell
.\destroy-lab.ps1
```

<#
.SYNOPSIS
  Automated Teardown & Destruction Script for Jira Data Center on AWS EKS

.DESCRIPTION
  This script safely and completely destroys all resources in the correct sequence:
  1. Uninstalls the Jira Helm release
  2. Deletes Kubernetes PVCs (releases AWS EBS gp3 volumes)
  3. Deletes the Jira namespace
  4. Waits for AWS Load Balancer Controller to delete the physical ALB in AWS
  5. Executes 'terraform destroy' to remove all foundational AWS and Kubernetes infrastructure
  6. Performs a sanity check to verify zero remaining billable AWS assets.

.EXAMPLE
  .\destroy-lab.ps1
#>

$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "   JIRA DATA CENTER ON AWS EKS - LAB TEARDOWN SCRIPT     " -ForegroundColor Red
Write-Host "==========================================================" -ForegroundColor Red
Write-Host "This will DESTROY ALL Jira Data Center infrastructure in AWS!" -ForegroundColor Yellow
$confirm = Read-Host "Are you sure you want to proceed? (Type 'yes' to continue)"

if ($confirm -ne "yes") {
    Write-Host "Teardown aborted by user." -ForegroundColor Cyan
    exit 0
}

# Ensure PATH includes kubectl and helm
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "`n>>> [1/4] Uninstalling Jira Helm Release & Cleaning Storage..." -ForegroundColor Cyan
$releaseCheck = helm list -n jira -q 2>$null
if ($releaseCheck -match "jira") {
    Write-Host "Uninstalling Helm release 'jira'..." -ForegroundColor Gray
    helm uninstall jira -n jira
} else {
    Write-Host "Helm release 'jira' not found or already uninstalled." -ForegroundColor Gray
}

Write-Host "Deleting PVCs in namespace 'jira' to release AWS EBS volumes..." -ForegroundColor Gray
kubectl delete pvc --all -n jira --timeout=60s 2>$null

Write-Host "Deleting 'jira' namespace..." -ForegroundColor Gray
kubectl delete namespace jira --timeout=60s 2>$null

Write-Host "`n>>> [2/4] Waiting for AWS ALB to finish deletion in AWS..." -ForegroundColor Cyan
$timeoutSeconds = 180
$elapsed = 0
while ($elapsed -lt $timeoutSeconds) {
    $albCheck = aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'jira')].LoadBalancerName" --output text 2>$null
    if ([string]::IsNullOrWhiteSpace($albCheck) -or $albCheck -eq "None") {
        Write-Host "AWS ALB has been successfully removed!" -ForegroundColor Green
        break
    }
    Write-Host "Waiting for ALB ($albCheck) to terminate in AWS... ($elapsed/$timeoutSeconds s)" -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    $elapsed += 15
}

Write-Host "`n>>> [3/4] Running Terraform Destroy..." -ForegroundColor Cyan
terraform destroy -var-file="env/dev/terraform.tfvars"

Write-Host "`n>>> [4/4] Final Verification: Checking Remaining AWS Resources..." -ForegroundColor Cyan
Write-Host "Active Load Balancers:" -ForegroundColor Gray
aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName" --output table

Write-Host "Active NAT Gateways:" -ForegroundColor Gray
aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" --query "NatGateways[*].NatGatewayId" --output table

Write-Host "Active EKS Clusters:" -ForegroundColor Gray
aws eks list-clusters --query "clusters" --output table

Write-Host "Active RDS Clusters:" -ForegroundColor Gray
aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier" --output table

Write-Host "Active EFS Filesystems:" -ForegroundColor Gray
aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output table

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  TEARDOWN COMPLETE! Verify that all outputs above are empty." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

<#
.SYNOPSIS
  Automated Jira Data Center Deployment Script for AWS EKS

.DESCRIPTION
  This script automates the complete end-to-end deployment of Jira Data Center on an existing
  AWS EKS cluster provisioned via Terraform:
  1. Checks required CLI tools (terraform, aws, kubectl, helm)
  2. Extracts infrastructure outputs from Terraform (RDS endpoint, Secrets ARN, Cluster Name)
  3. Updates kubeconfig to authenticate with the EKS cluster
  4. Retrieves RDS master credentials from AWS Secrets Manager
  5. Creates the 'jira' Kubernetes namespace and 'jira-db-secret'
  6. Adds & updates the official Atlassian Helm repository
  7. Configures and deploys the Jira Data Center Helm chart with production values
  8. Waits for the AWS Application Load Balancer (ALB) to provision and retrieves the DNS URL
  9. Verifies pod health and outputs the ready-to-use Jira Web UI URL.

.EXAMPLE
  .\deploy-jira.ps1
#>

$ErrorActionPreference = "Stop"

# Ensure PATH includes all machine/user tools
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  JIRA DATA CENTER ON AWS EKS - AUTOMATED DEPLOYMENT      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. PREREQUISITE CHECKS
# -----------------------------------------------------------------------------
Write-Host "`n>>> [1/7] Checking Required CLI Tools..." -ForegroundColor Yellow

$requiredTools = @("terraform", "aws", "kubectl", "helm")
foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: '$tool' is not installed or not in system PATH." -ForegroundColor Red
        Write-Host "Please install $tool and restart your terminal." -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] $tool is available" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. FETCH TERRAFORM OUTPUTS
# -----------------------------------------------------------------------------
Write-Host "`n>>> [2/7] Extracting Terraform Infrastructure Outputs..." -ForegroundColor Yellow

try {
    $clusterName = terraform output -raw cluster_name 2>$null
    $rdsEndpoint = terraform output -raw rds_cluster_endpoint 2>$null
    $secretArn   = terraform output -raw rds_master_user_secret_arn 2>$null
    $efsId       = terraform output -raw efs_file_system_id 2>$null
} catch {
    $clusterName = $null
}

if ([string]::IsNullOrWhiteSpace($clusterName) -or [string]::IsNullOrWhiteSpace($rdsEndpoint)) {
    Write-Host "ERROR: Could not retrieve Terraform outputs!" -ForegroundColor Red
    Write-Host "Have you run 'terraform apply' yet?" -ForegroundColor Yellow
    Write-Host "Please run: terraform apply -var-file='env/dev/terraform.tfvars' first." -ForegroundColor Yellow
    exit 1
}

Write-Host "  EKS Cluster Name       : $clusterName" -ForegroundColor Cyan
Write-Host "  RDS Postgres Endpoint  : $rdsEndpoint" -ForegroundColor Cyan
Write-Host "  EFS File System ID     : $efsId" -ForegroundColor Cyan
Write-Host "  RDS Secrets Manager ARN: $secretArn" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 3. CONFIGURE KUBECTL CONTEXT
# -----------------------------------------------------------------------------
Write-Host "`n>>> [3/7] Updating Kubernetes Kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --region us-east-1 --name $clusterName | Out-Null
Write-Host "  [OK] Successfully authenticated with EKS cluster '$clusterName'" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. RETRIEVE RDS CREDENTIALS & CREATE K8S SECRET
# -----------------------------------------------------------------------------
Write-Host "`n>>> [4/7] Retrieving Database Credentials & Creating Secrets..." -ForegroundColor Yellow

$secretValueRaw = aws secretsmanager get-secret-value --secret-id "$secretArn" --query SecretString --output text
try {
    $secretJson = $secretValueRaw | ConvertFrom-Json
    $dbUsername = if ($secretJson.username) { $secretJson.username } else { "postgres" }
    $dbPassword = $secretJson.password
} catch {
    $dbUsername = "postgres"
    $dbPassword = $secretValueRaw.Trim()
}

# Create Jira namespace if not exists
kubectl create namespace jira --dry-run=client -o yaml | kubectl apply -f - | Out-Null

# Create or update jira-db-secret
kubectl create secret generic jira-db-secret `
    --namespace jira `
    --from-literal=username="$dbUsername" `
    --from-literal=password="$dbPassword" `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null

Write-Host "  [OK] Namespace 'jira' and Secret 'jira-db-secret' ready" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. CONFIGURE JIRA VALUES FILE
# -----------------------------------------------------------------------------
Write-Host "`n>>> [5/7] Preparing Helm Values Configuration..." -ForegroundColor Yellow

$valuesPath = ".\helm\jira-values.yaml"

$jiraValuesContent = @"
# jira-values.yaml
# Official Atlassian Jira Data Center Helm Chart Values
# Initial setup starts with replicaCount: 1 until setup wizard completes.

replicaCount: 1

jira:
  service:
    type: ClusterIP
    port: 80

  resources:
    container:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "3"
        memory: "8Gi"
    jvm:
      minHeap: "2g"
      maxHeap: "4g"

# Database configuration pointing to Aurora PostgreSQL
database:
  type: postgres72
  url: "jdbc:postgresql://${rdsEndpoint}:5432/jiradb"
  driver: org.postgresql.Driver
  credentials:
    secretName: jira-db-secret
    usernameSecretKey: username
    passwordSecretKey: password

# Storage Configuration
volumes:
  localHome:
    persistentVolumeClaim:
      create: true
      storageClassName: "gp2"
      resources:
        requests:
          storage: 50Gi

  sharedHome:
    persistentVolumeClaim:
      create: true
      storageClassName: "efs-sc"
      resources:
        requests:
          storage: 100Gi

# Ingress: Triggers AWS Load Balancer Controller to provision an internet-facing ALB
ingress:
  create: true
  className: "alb"
  https: false
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    # Health Check configuration (/status returns 200, / returns 302)
    alb.ingress.kubernetes.io/healthcheck-path: /status
    alb.ingress.kubernetes.io/success-codes: "200,302"
    # Sticky Sessions (Mandatory for Jira Data Center clustering)
    alb.ingress.kubernetes.io/affinity: cookie
    alb.ingress.kubernetes.io/affinity-mode: persistent
    alb.ingress.kubernetes.io/session-cookie-name: AWSALB
    alb.ingress.kubernetes.io/session-cookie-expires: "86400"
  path: "/"
"@

[System.IO.File]::WriteAllText($valuesPath, $jiraValuesContent, [System.Text.Encoding]::UTF8)
Write-Host "  [OK] Values file '$valuesPath' generated with UTF-8 encoding" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. DEPLOY JIRA VIA HELM
# -----------------------------------------------------------------------------
Write-Host "`n>>> [6/7] Deploying Jira Data Center via Helm..." -ForegroundColor Yellow

helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts | Out-Null
helm repo update atlassian-data-center | Out-Null

helm upgrade --install jira atlassian-data-center/jira `
    --namespace jira `
    -f $valuesPath

Write-Host "  [OK] Helm release 'jira' deployed successfully" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. WAIT FOR ALB INGRESS & POD READINESS
# -----------------------------------------------------------------------------
Write-Host "`n>>> [7/7] Waiting for AWS Application Load Balancer to provision..." -ForegroundColor Yellow

$albHost = ""
$retries = 0
$maxRetries = 24

while ($retries -lt $maxRetries) {
    $albHost = kubectl get ingress jira -n jira -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($albHost)) {
        break
    }
    Write-Host "  Waiting for ALB DNS hostname... ($($retries * 10)s / 240s)" -ForegroundColor Gray
    Start-Sleep -Seconds 10
    $retries++
}

if ([string]::IsNullOrWhiteSpace($albHost)) {
    Write-Host "WARNING: ALB hostname was not ready within timeout. Check 'kubectl get ingress -n jira'." -ForegroundColor Yellow
} else {
    Write-Host "`n  [SUCCESS] AWS Application Load Balancer is ACTIVE!" -ForegroundColor Green
    Write-Host "  ALB Hostname: $albHost" -ForegroundColor Cyan

    # Inject the discovered host into jira-values.yaml so Tomcat configures proxyName accurately
    if (-not (Select-String -Path $valuesPath -Pattern "host: `"$albHost`"")) {
        $updatedValues = [System.IO.File]::ReadAllText($valuesPath)
        $updatedValues = $updatedValues -replace 'https: false', "https: false`n  host: `"$albHost`""
        [System.IO.File]::WriteAllText($valuesPath, $updatedValues, [System.Text.Encoding]::UTF8)
        Write-Host "  Updated values file with host: $albHost" -ForegroundColor Gray
        helm upgrade jira atlassian-data-center/jira --namespace jira -f $valuesPath | Out-Null
    }
}

Write-Host "`nWaiting for pod 'jira-0' to reach Ready status (this may take 2-3 minutes for DB setup)..." -ForegroundColor Yellow
kubectl wait --namespace jira --for=condition=Ready pod/jira-0 --timeout=300s 2>$null

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   JIRA DATA CENTER DEPLOYMENT COMPLETE!                 " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

if (-not [string]::IsNullOrWhiteSpace($albHost)) {
    Write-Host "`nAccess Jira in your browser:" -ForegroundColor Yellow
    Write-Host "  URL: http://$albHost" -ForegroundColor Cyan
} else {
    Write-Host "`nCheck your Ingress URL using:" -ForegroundColor Yellow
    Write-Host "  kubectl get ingress -n jira" -ForegroundColor Cyan
}

Write-Host "`nHelpful troubleshooting commands:" -ForegroundColor Gray
Write-Host "  Check Pods   : kubectl get pods -n jira" -ForegroundColor Gray
Write-Host "  Check Logs   : kubectl logs -f jira-0 -n jira -c jira" -ForegroundColor Gray
Write-Host "  Check Ingress: kubectl describe ingress jira -n jira" -ForegroundColor Gray
Write-Host "  Teardown Lab : .\destroy-lab.ps1" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Green

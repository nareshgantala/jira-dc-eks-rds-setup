# Kubernetes & AWS EKS: The Ultimate "Break & Fix" Chaos Engineering Lab Manual

> *"You only truly understand a distributed system when you can break it on purpose, diagnose the exact failure from logs and events, and bring it back to life."*

This manual contains **17 hands-on Break & Fix labs** designed specifically for your **Jira Data Center on AWS EKS & Aurora PostgreSQL** infrastructure. Each lab targets a real-world production failure scenario across Storage, Networking, IAM/IRSA, Ingress, Database, and Compute.

---

## Lab Index

| # | Lab Title | Target Component | Failure Symptom | Difficulty |
|---|---|---|---|---|
| **01** | [The Stolen Badge (IRSA SA Annotation Corrupted)](#lab-01-the-stolen-badge-irsa-serviceaccount-annotation-corrupted) | IAM / OIDC / IRSA | Ingress has no Address; ALB Controller CrashLoopBackOff | 🟡 Medium |
| **02** | [The Trust Policy Lockout (OIDC Subject Mismatch)](#lab-02-the-trust-policy-lockout-oidc-subject-mismatch) | AWS IAM Trust Policy | `AssumeRoleWithWebIdentity` AccessDenied | 🔴 Advanced |
| **03** | [The Unhealthy Target (ALB Healthcheck Mismatch)](#lab-03-the-unhealthy-target-alb-healthcheck-path-mismatch) | Ingress / Target Group | HTTP `503 Service Temporarily Unavailable` | 🟢 Beginner |
| **04** | [The 403 Forbidden Protocol Mismatch (HTTP vs HTTPS)](#lab-04-the-403-forbidden-protocol-mismatch-http-vs-https) | Reverse Proxy / Tomcat | HTTP `403 Forbidden` (`XSRF checks failed`) | 🟡 Medium |
| **05** | [The Missing IngressClass (Ghost Ingress)](#lab-05-the-missing-ingressclass-ghost-ingress) | IngressClass / Controller | Ingress created but completely ignored | 🟢 Beginner |
| **06** | [The Missing Subnet Tag (ALB Discovery Failure)](#lab-06-the-missing-subnet-tag-alb-discovery-failure) | AWS VPC Subnet Tags | ALB Controller: `couldn't auto-discover subnets` | 🟡 Medium |
| **07** | [Target Type Mismatch (`ip` vs `instance`)](#lab-07-target-type-mismatch-ip-vs-instance) | ALB Target Type | Targets Unhealthy on NodePort | 🟡 Medium |
| **08** | [The Sticky Session Amnesia (Cluster Ping-Pong)](#lab-08-the-sticky-session-amnesia-cluster-ping-pong) | Ingress Session Cookie | Random logouts, session drops across pods | 🟡 Medium |
| **09** | [The Phantom StorageClass (Invalid SC Name)](#lab-09-the-phantom-storageclass-invalid-sc-name) | PVC / StorageClass | Pod stuck in `Pending` indefinitely | 🟢 Beginner |
| **10** | [The EFS NFS Firewall Block (Port 2049 Severed)](#lab-10-the-efs-nfs-firewall-block-port-2049-severed) | AWS Security Group (`efs-sg`) | Pod stuck in `Init:0/1` (`mount failed: Connection timed out`) | 🟡 Medium |
| **11** | [The EFS Access Point Identity Crisis (POSIX Perms)](#lab-11-the-efs-access-point-identity-crisis-posix-perms) | StorageClass POSIX / Init Container | `java.io.FileNotFoundException: Permission denied` | 🔴 Advanced |
| **12** | [The Secret Sabotage (Corrupted DB Credentials)](#lab-12-the-secret-sabotage-corrupted-db-credentials) | Kubernetes Secret | Pod CrashLoopBackOff (`PSQLException: FATAL: password auth failed`) | 🟢 Beginner |
| **13** | [The Database Firewall Sever (Port 5432 Blocked)](#lab-13-the-database-firewall-sever-port-5432-blocked) | AWS Security Group (`rds-sg`) | Pod hangs on DB connection timeout | 🟢 Beginner |
| **14** | [The Greedy Pod (CPU/Memory Over-Allocation)](#lab-14-the-greedy-pod-cpumemory-over-allocation) | Resource Requests / Limits | Pod stuck in `Pending` (`0/2 nodes available: Insufficient cpu`) | 🟢 Beginner |
| **15** | [The Out Of Memory Terminator (OOMKilled Exit Code 137)](#lab-15-the-out-of-memory-terminator-oomkilled-exit-code-137) | JVM Heap vs Container Limit | Container killed by Linux Kernel (`OOMKilled`) | 🟡 Medium |
| **16** | [CoreDNS Blackout (Cluster-Wide Name Resolution Failure)](#lab-16-coredns-blackout-cluster-wide-name-resolution-failure) | CoreDNS Deployment | Pod cannot resolve RDS endpoint or Kubernetes services | 🟡 Medium |
| **17** | [VPC DNS Hostname Blindspot (EFS Regional DNS Failure)](#lab-17-vpc-dns-hostname-blindspot-efs-regional-dns-failure) | AWS VPC DNS Attributes | `Failed to resolve fs-xxxx.efs.us-east-1.amazonaws.com` | 🔴 Advanced |

---

## How to Conduct These Labs

For each lab, follow the exact 4-step scientific method:
1. **Break**: Execute the break command.
2. **Observe**: Check pod status, events, logs, and HTTP responses.
3. **Diagnose**: Run the diagnostic detective commands to locate the exact root cause.
4. **Fix**: Run the fix command and verify full system recovery.

---

### Lab 01: The Stolen Badge (IRSA ServiceAccount Annotation Corrupted)

#### Concept
Kubernetes pods obtain AWS permissions via **IRSA** (IAM Roles for Service Accounts). The pod's ServiceAccount has an annotation `eks.amazonaws.com/role-arn`. If this annotation is missing or pointing to a non-existent IAM role, the AWS STS admission webhook fails, and the pod receives no temporary AWS credentials.

#### 1. How to Break It:
Corrupt the IAM role annotation on the AWS Load Balancer Controller service account:
```powershell
kubectl annotate sa aws-load-balancer-controller -n kube-system eks.amazonaws.com/role-arn="arn:aws:iam::123456789012:role/fake-nonexistent-role" --overwrite
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

#### 2. What Symptoms You Will Observe:
* The AWS Load Balancer Controller pods will crash or log continuous authorization errors.
* Any changes to the Jira Ingress will be ignored. If an ALB was pending, the `ADDRESS` column will remain blank forever!

#### 3. Detective Work (How to Diagnose):
```powershell
# Check controller pod status
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Read the controller logs (Look for WebIdentityErr / AccessDenied)
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=30

# Inspect the ServiceAccount annotation
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml | Select-String -Pattern "role-arn" -Context 1,2
```
*Diagnostic Proof*: You will see `WebIdentityErr: AccessDenied` or `role arn:aws:iam::123456789012:role/fake-nonexistent-role not found`.

#### 4. How to Fix It:
Re-apply the real IAM Role ARN created by Terraform:
```powershell
$REAL_ROLE_ARN = (aws iam list-roles --query "Roles[?contains(RoleName, 'alb-controller-role')].Arn" --output text)
kubectl annotate sa aws-load-balancer-controller -n kube-system eks.amazonaws.com/role-arn="$REAL_ROLE_ARN" --overwrite
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
kubectl rollout status deployment aws-load-balancer-controller -n kube-system
```

---

### Lab 02: The Trust Policy Lockout (OIDC Subject Mismatch)

#### Concept
AWS IAM Roles for Service Accounts enforce a **Trust Relationship Policy**. AWS STS checks: *"Is the JWT token signed by this EKS cluster's OIDC provider, AND does the token's subject (`sub`) exactly match `system:serviceaccount:<namespace>:<serviceaccount>`?"* If there is a typo in either, STS immediately slams the door shut.

#### 1. How to Break It:
Lock out the EFS CSI driver by altering its trust policy to expect a wrong service account:
```powershell
$ROLE_NAME = (aws iam list-roles --query "Roles[?contains(RoleName, 'efs-csi-role')].RoleName" --output text)
$OIDC_URL = (terraform output -raw oidc_provider_url)

# Create a broken trust policy matching a fake SA
$BROKEN_TRUST = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::$((aws sts get-caller-identity --query Account --output text)):oidc-provider/$OIDC_URL" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "$OIDC_URL:sub": "system:serviceaccount:kube-system:wrong-serviceaccount",
          "$OIDC_URL:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
"@
$BROKEN_TRUST | Out-File -FilePath "broken-trust.json" -Encoding ascii
aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://broken-trust.json
Remove-Item "broken-trust.json"

# Restart the EFS CSI controller
kubectl rollout restart deployment efs-csi-controller -n kube-system
```

#### 2. What Symptoms You Will Observe:
* The EFS CSI controller pod logs: `Not authorized to perform sts:AssumeRoleWithWebIdentity`.
* Any new PVC requesting `efs-sc` will be stuck in `Pending` because the CSI controller cannot call AWS EFS APIs to create access points!

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver -c efs-plugin --tail=40
```
*Diagnostic Proof*: `An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation`.

#### 4. How to Fix It:
Restore the wildcard trust policy in Terraform:
```powershell
terraform apply -target=aws_iam_role.efs_csi_role -var-file="env/dev/terraform.tfvars" -auto-approve
kubectl rollout restart deployment efs-csi-controller -n kube-system
```

---

### Lab 03: The Unhealthy Target (ALB Healthcheck Path Mismatch)

#### Concept
The AWS Application Load Balancer continuously queries target pods on a designated healthcheck path. If the target group receives an unexpected HTTP response code (e.g. 404 or 302 when expecting 200), the target is marked `unhealthy`. When all targets in a target group are unhealthy, the ALB returns `HTTP 503 Service Temporarily Unavailable`.

#### 1. How to Break It:
Change the healthcheck path to a non-existent endpoint in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml):
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /broken-nonexistent-path
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* The Jira pod is `1/1 Running` inside Kubernetes.
* BUT accessing the ALB URL in your browser gives: `503 Service Temporarily Unavailable`!

#### 3. Detective Work (How to Diagnose):
```powershell
# 1. Fetch the AWS Target Group ARN
$TG_ARN = (kubectl get targetgroupbinding -n jira -o jsonpath='{.items[0].spec.targetGroupARN}')

# 2. Query target health from AWS
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```
*Diagnostic Proof*:
`"TargetHealth": { "State": "unhealthy", "Reason": "Target.ResponseCodeMismatch", "Description": "Health checks failed with these codes: [404]" }`

#### 4. How to Fix It:
Change the annotation back in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml):
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /status
alb.ingress.kubernetes.io/success-codes: "200,302"
```
Re-apply:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```
Verify target returns to `State: healthy`.

---

### Lab 04: The 403 Forbidden Protocol Mismatch (HTTP vs HTTPS)

#### Concept
Jira Data Center runs inside an Apache Tomcat servlet container. Tomcat can be configured with proxy properties (`scheme`, `secure`, `proxyPort`). If Jira receives an incoming HTTP request on port 80, but Tomcat was told `scheme="https"`, Jira's Cross-Site Request Forgery (XSRF) token validator flags the protocol mismatch (`http` origin vs `https` base URL) and blocks all form submissions with `403 Forbidden`.

#### 1. How to Break It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), change:
```yaml
ingress:
  https: true
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* The web page loads, but when submitting any setup or login form, the screen shows:
  **`Forbidden (403) - Encountered a "403 - Forbidden" error while loading this page`**.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c jira | Select-String -Pattern "XSRF checks failed" -Context 0,2
```
*Diagnostic Proof*: `XSRF checks failed for action '...SetupApplicationProperties!execute' (recoverable: false, token present: true)`.

#### 4. How to Fix It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), ensure:
```yaml
ingress:
  https: false
  host: "k8s-jira-jira-2521efea0a-496804775.us-east-1.elb.amazonaws.com"
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

---

### Lab 05: The Missing IngressClass (Ghost Ingress)

#### Concept
Kubernetes clusters can have multiple ingress controllers (e.g., NGINX, Traefik, AWS ALB). Each controller only processes Ingress resources that declare its specific `ingressClassName`. If `ingressClassName` is mistyped or omitted, the AWS Load Balancer Controller completely ignores the manifest.

#### 1. How to Break It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), change:
```yaml
ingress:
  className: "nginx"
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* Ingress is created, but the `ADDRESS` column stays completely blank forever! No AWS ALB is provisioned.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl get ingress -n jira
kubectl describe ingress jira -n jira
```
*Diagnostic Proof*: The `Events:` section at the bottom of `kubectl describe ingress` is completely empty. The ALB controller never even touched it because `Class: nginx` did not match `alb`.

#### 4. How to Fix It:
Change `className: "alb"` in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml) and run `helm upgrade`.

---

### Lab 06: The Missing Subnet Tag (ALB Discovery Failure)

#### Concept
The AWS Load Balancer Controller automatically discovers which subnets to deploy public ALBs into by searching for the tag:
`kubernetes.io/role/elb = 1`.
If this tag is missing from the public subnets, the controller cannot determine where to place the load balancer ENIs and fails to create the ALB.

#### 1. How to Break It:
Delete the tag from one of the public subnets:
```powershell
$SUBNET_ID = (terraform output -json public_subnet_ids | ConvertFrom-Json)[0]
aws ec2 delete-tags --resources $SUBNET_ID --tags Key=kubernetes.io/role/elb
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

#### 2. What Symptoms You Will Observe:
* Ingress fails to provision an ALB.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=40 | Select-String -Pattern "subnet"
```
*Diagnostic Proof*: `Failed build model due to couldn't auto-discover subnets: unable to resolve at least 2 subnets across different AZs with tag kubernetes.io/role/elb=1`.

#### 4. How to Fix It:
Re-add the tag:
```powershell
aws ec2 create-tags --resources $SUBNET_ID --tags Key=kubernetes.io/role/elb,Value=1
```

---

### Lab 07: Target Type Mismatch (`ip` vs `instance`)

#### Concept
AWS ALB supports two target types:
* `target-type: ip`: Packets route directly to Pod private IPs (enabled by AWS VPC CNI).
* `target-type: instance`: Packets route to EC2 worker node IPs on a Kubernetes `NodePort`.
Because Jira's Kubernetes Service is `ClusterIP` (not `NodePort`), using `instance` causes all traffic to hit closed ports on the EC2 host.

#### 1. How to Break It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), change:
```yaml
alb.ingress.kubernetes.io/target-type: instance
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* ALB Target Group targets switch to EC2 Node IDs (e.g., `i-0abc...`) on port 80.
* Targets fail health checks immediately because no NodePort is listening on the EC2 host!

#### 3. Detective Work (How to Diagnose):
```powershell
$TG_ARN = (kubectl get targetgroupbinding -n jira -o jsonpath='{.items[0].spec.targetGroupARN}')
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```
*Diagnostic Proof*: `Target.FailedHealthChecks: Connection refused`.

#### 4. How to Fix It:
Change `target-type: ip` in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml) and run `helm upgrade`.

---

### Lab 08: The Sticky Session Amnesia (Cluster Ping-Pong)

#### Concept
Jira Data Center stores active user web sessions in Tomcat memory on the specific node where the user logged in. If an ALB distributes consecutive requests round-robin across pods, requests hit nodes that do not have the user's session, causing random session drops, unexpected logouts, and form submission errors. Sticky sessions (`AWSALB` cookie) ensure all requests from a browser stick to the same pod.

#### 1. How to Break It:
Comment out the affinity annotations in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml):
```yaml
# alb.ingress.kubernetes.io/affinity: cookie
# alb.ingress.kubernetes.io/session-cookie-name: AWSALB
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* If scaled to 2 replicas (`replicaCount: 2`), clicking links in Jira causes random redirect loops to the login screen.

#### 3. Detective Work (How to Diagnose):
```powershell
curl.exe -s -i "http://k8s-jira-jira-2521efea0a-496804775.us-east-1.elb.amazonaws.com" | Select-String -Pattern "Set-Cookie"
```
*Diagnostic Proof*: Notice `Set-Cookie: AWSALB=...` is completely missing from the response headers!

#### 4. How to Fix It:
Re-enable cookie affinity in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml) and run `helm upgrade`.

---

### Lab 09: The Phantom StorageClass (Invalid SC Name)

#### Concept
When a pod requests dynamic volume provisioning, Kubernetes searches for a matching `StorageClass`. If the PVC references a StorageClass that does not exist in the cluster, volume provisioning stops completely, and the pod cannot start.

#### 1. How to Break It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), change:
```yaml
volumes:
  localHome:
    persistentVolumeClaim:
      storageClassName: "non-existent-sc"
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* Pod is stuck in `Pending` state indefinitely.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl get pods -n jira
kubectl describe pod jira-0 -n jira
kubectl get pvc -n jira
kubectl describe pvc local-home-jira-0 -n jira
```
*Diagnostic Proof*: In `kubectl describe pvc`:
`Warning ProvisioningFailed: storageclass.storage.k8s.io "non-existent-sc" not found`.

#### 4. How to Fix It:
Change `storageClassName: "gp2"` in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml) and run `helm upgrade`.

---

### Lab 10: The EFS NFS Firewall Block (Port 2049 Severed)

#### Concept
Amazon EFS operates over the NFSv4 protocol on TCP port **2049**. EKS worker nodes communicate with the EFS mount target network interfaces inside the private subnets. If the EFS Security Group blocks port 2049, the Linux kernel NFS client hangs and times out.

#### 1. How to Break It:
Delete the ingress rule on `efs_sg`:
```powershell
$EFS_SG = (aws ec2 describe-security-groups --filters "Name=group-name,Values=*efs-sg*" --query "SecurityGroups[0].GroupId" --output text)
aws ec2 revoke-security-group-ingress --group-id $EFS_SG --protocol tcp --port 2049 --cidr 10.0.0.0/16
kubectl delete pod jira-0 -n jira
```

#### 2. What Symptoms You Will Observe:
* `jira-0` pod is stuck in `ContainerCreating` or `Init:0/1`.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl describe pod jira-0 -n jira | Select-String -Pattern "MountVolume" -Context 0,3
```
*Diagnostic Proof*: `MountVolume.SetUp failed for volume "..." : mount failed: exit status 32 (Connection timed out)`.

#### 4. How to Fix It:
Re-allow NFS port 2049:
```powershell
aws ec2 authorize-security-group-ingress --group-id $EFS_SG --protocol tcp --port 2049 --cidr 10.0.0.0/16
```
The pod will automatically mount within 30 seconds!

---

### Lab 11: The EFS Access Point Identity Crisis (POSIX Perms)

#### Concept
The Atlassian Jira container runs as an unprivileged user (`uid: 2001`, `gid: 2001`). When mounting an EFS volume, if the root directory permissions are owned by `root:root (0:0)` with mode `755`, the Jira process cannot write its cluster locks or plugin files into the shared home.

#### 1. How to Break It:
Delete the init container `nfs-permission-fixer` permissions by scaling it down or removing directory permissions.

#### 2. What Symptoms You Will Observe:
* `jira-0` pod crashes or logs permission errors on `/var/atlassian/application-data/jira/shared`.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c jira | Select-String -Pattern "Permission denied" -Context 0,2
```
*Diagnostic Proof*: `java.io.FileNotFoundException: /var/atlassian/application-data/jira/shared/cluster.properties (Permission denied)`.

#### 4. How to Fix It:
Verify that `kubernetes_storage_class_v1.efs_sc` in [main.tf](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/main.tf) sets `directoryPerms: "700"`, `gidRangeStart: "2001"`, and that the `nfs-permission-fixer` init container runs `chown -R 2001:2001 /var/atlassian/application-data/jira/shared`.

---

### Lab 12: The Secret Sabotage (Corrupted DB Credentials)

#### Concept
Jira reads database connection parameters and credentials from Kubernetes Secrets (`jira-db-secret`). If the secret is missing, corrupted, or has an invalid password, Jira cannot connect to Aurora PostgreSQL.

#### 1. How to Break It:
Overwrite `jira-db-secret` with an invalid password:
```powershell
kubectl create secret generic jira-db-secret -n jira `
  --from-literal=username="postgres" `
  --from-literal=password="CompletelyWrongPassword123!" `
  --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod jira-0 -n jira
```

#### 2. What Symptoms You Will Observe:
* `jira-0` fails to initialize.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c jira --tail=40 | Select-String -Pattern "PSQLException" -Context 1,2
```
*Diagnostic Proof*: `org.postgresql.util.PSQLException: FATAL: password authentication failed for user "postgres"`.

#### 4. How to Fix It:
Fetch the authentic master password from AWS Secrets Manager and recreate the secret:
```powershell
$SECRET_ARN = (terraform output -raw rds_master_user_secret_arn)
$DB_PASSWORD = (aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text | ConvertFrom-Json).password

kubectl create secret generic jira-db-secret -n jira `
  --from-literal=username="postgres" `
  --from-literal=password="$DB_PASSWORD" `
  --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod jira-0 -n jira
```

---

### Lab 13: The Database Firewall Sever (Port 5432 Blocked)

#### Concept
Aurora PostgreSQL listens on port **5432**. Security Group `rds_sg` restricts ingress exclusively to traffic originating from within the VPC CIDR (`10.0.0.0/16`). If port 5432 is revoked, Jira cannot reach the database cluster.

#### 1. How to Break It:
Revoke port 5432 ingress:
```powershell
$RDS_SG = (aws ec2 describe-security-groups --filters "Name=group-name,Values=*rds-sg*" --query "SecurityGroups[0].GroupId" --output text)
aws ec2 revoke-security-group-ingress --group-id $RDS_SG --protocol tcp --port 5432 --cidr 10.0.0.0/16
kubectl delete pod jira-0 -n jira
```

#### 2. What Symptoms You Will Observe:
* Pod startup hangs indefinitely during the database connectivity check.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c jira --tail=30
```
*Diagnostic Proof*: `Connection to jira-dc-rds-cluster...:5432 refused` or `Connection timed out`.

#### 4. How to Fix It:
Re-authorize port 5432:
```powershell
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 5432 --cidr 10.0.0.0/16
```

---

### Lab 14: The Greedy Pod (CPU/Memory Over-Allocation)

#### Concept
When a pod requests resources (`requests.cpu` and `requests.memory`), the Kubernetes Scheduler searches for a worker node with enough unreserved allocatable capacity. If requests exceed node capacity (e.g. asking for 32 CPUs on an `m5.xlarge` node with 4 CPUs), the scheduler cannot place the pod.

#### 1. How to Break It:
In [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml), request impossible resources:
```yaml
jira:
  resources:
    container:
      requests:
        cpu: "32"
        memory: "128Gi"
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* `jira-0` is stuck in `Pending` state.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl get pods -n jira
kubectl describe pod jira-0 -n jira | Select-String -Pattern "FailedScheduling" -Context 0,2
```
*Diagnostic Proof*: `Warning FailedScheduling: 0/2 nodes are available: 2 Insufficient cpu, 2 Insufficient memory`.

#### 4. How to Fix It:
Restore realistic requests (`cpu: "2"`, `memory: "4Gi"`) in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml) and run `helm upgrade`.

---

### Lab 15: The Out Of Memory Terminator (OOMKilled Exit Code 137)

#### Concept
Kubernetes enforces container memory limits using Linux `cgroups`. If a Java process inside a container allocates more heap memory than the container's cgroup memory limit, the Linux Kernel Out-Of-Memory Killer instantly terminates the container with signal 9 (`SIGKILL`, exit code 137).

#### 1. How to Break It:
Set the container memory limit smaller than the JVM heap in [helm/jira-values.yaml](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/helm/jira-values.yaml):
```yaml
jira:
  resources:
    container:
      limits:
        memory: "1Gi"
    jvm:
      maxHeap: "3g"
```
Upgrade Helm:
```powershell
helm upgrade jira atlassian-data-center/jira --namespace jira -f .\helm\jira-values.yaml
```

#### 2. What Symptoms You Will Observe:
* Pod restarts continuously (`CrashLoopBackOff`, Restarts incrementing).

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl get pods -n jira
kubectl describe pod jira-0 -n jira | Select-String -Pattern "OOMKilled|Exit Code" -Context 1,2
```
*Diagnostic Proof*: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`.

#### 4. How to Fix It:
Ensure container memory limit (`8Gi`) is always greater than JVM max heap (`4g`) + JVM metaspace and OS overhead:
```yaml
jira:
  resources:
    container:
      limits:
        memory: "8Gi"
    jvm:
      maxHeap: "4g"
```
Re-apply with `helm upgrade`.

---

### Lab 16: CoreDNS Blackout (Cluster-Wide Name Resolution Failure)

#### Concept
CoreDNS is the in-cluster DNS server for Kubernetes. It translates service names (e.g. `jira.jira.svc.cluster.local`) and forwards external queries (e.g. RDS Aurora endpoint) to the VPC Route 53 Resolver (`10.0.0.2`). If CoreDNS is scaled down or down, all name resolution fails.

#### 1. How to Break It:
Scale CoreDNS replicas to zero:
```powershell
kubectl scale deployment coredns -n kube-system --replicas=0
kubectl delete pod jira-0 -n jira
```

#### 2. What Symptoms You Will Observe:
* `jira-0` pod fails during startup because it cannot resolve the RDS database hostname: `jira-dc-rds-cluster.cluster-...rds.amazonaws.com`!

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c jira --tail=30 | Select-String -Pattern "UnknownHostException"
```
*Diagnostic Proof*: `java.net.UnknownHostException: jira-dc-rds-cluster...`.

#### 4. How to Fix It:
Scale CoreDNS back to 2 replicas:
```powershell
kubectl scale deployment coredns -n kube-system --replicas=2
kubectl rollout status deployment coredns -n kube-system
```

---

### Lab 17: VPC DNS Hostname Blindspot (EFS Regional DNS Failure)

#### Concept
Amazon EFS filesystems use DNS names in the format: `fs-xxxxxx.efs.<region>.amazonaws.com`. For EC2 nodes in a VPC to resolve these names to private mount target IPs, the VPC must have both attributes enabled:
* `enable_dns_support = true`
* `enable_dns_hostnames = true`
If `enable_dns_hostnames` is disabled, Route 53 Resolver returns `NXDOMAIN` for EFS DNS queries.

#### 1. How to Break It:
Disable DNS hostnames on the VPC:
```powershell
$VPC_ID = (terraform output -raw vpc_id)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --no-enable-dns-hostnames
kubectl delete pod jira-0 -n jira
```

#### 2. What Symptoms You Will Observe:
* `jira-0` pod stuck in `Init:0/1`.

#### 3. Detective Work (How to Diagnose):
```powershell
kubectl logs jira-0 -n jira -c nfs-permission-fixer
```
*Diagnostic Proof*: `Failed to resolve "fs-09205c11977baaf08.efs.us-east-1.amazonaws.com"`.

#### 4. How to Fix It:
Re-enable DNS hostnames on the VPC:
```powershell
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
```
The pod will mount and proceed within 20 seconds!

---

## 🎯 Final Mastery Checklist

If you can successfully run and resolve all 17 labs in this guide, you will possess a deeper, more practical understanding of **Kubernetes on AWS EKS** than 90% of DevOps engineers in technical interviews:

- [ ] Mastered IRSA WebIdentity and OIDC Token Authentication (Labs 1 & 2)
- [ ] Mastered AWS Application Load Balancer Ingress Controller (Labs 3, 4, 5, 6, 7, 8)
- [ ] Mastered Kubernetes Storage Classes, EBS (RWO) & EFS (RWX) (Labs 9, 10, 11)
- [ ] Mastered Kubernetes Secrets & Database Security Groups (Labs 12 & 13)
- [ ] Mastered Pod Scheduling, Resource Quotas & OOMKilled Signals (Labs 14 & 15)
- [ ] Mastered CoreDNS & VPC Route 53 Resolution (Labs 16 & 17)

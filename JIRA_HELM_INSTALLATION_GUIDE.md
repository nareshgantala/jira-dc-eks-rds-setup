# Jira Data Center Helm Chart Installation Guide

This guide provides step-by-step instructions to deploy **Atlassian Jira Data Center** onto your AWS EKS cluster, leveraging the Aurora Serverless v2 PostgreSQL database, Amazon EFS shared storage, and AWS Load Balancer Controller provisioned by your Terraform infrastructure.

---

## 1. Prerequisites & Environment Setup

### 1.1 Connect `kubectl` to your EKS Cluster
Once you have run `terraform apply -var-file="env/dev/terraform.tfvars"`, authenticate your local `kubectl` with the cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name jira-dc-dev-eks-cluster
```

Verify your cluster connectivity and worker nodes:
```bash
kubectl get nodes
```
*(You should see 2 healthy `m5.xlarge` nodes).*

Verify that the essential add-ons and controllers are running:
```bash
kubectl get pods -n kube-system
```
Make sure you see:
* `aws-load-balancer-controller-*` (2 pods)
* `ebs-csi-controller-*` & `ebs-csi-node-*`
* `efs-csi-controller-*` & `efs-csi-node-*`

---

## 2. Retrieve Database Credentials

Terraform manages your Aurora PostgreSQL master password securely inside **AWS Secrets Manager**. Retrieve the generated password using the AWS CLI:

```bash
# 1. Get the secret ARN from Terraform output
SECRET_ARN=$(terraform output -raw rds_master_user_secret_arn)

# 2. Fetch the password from AWS Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text | jq -r .password)

# Print to verify (or copy it for the next step)
echo "Retrieved DB password successfully"
```

---

## 3. Prepare the Kubernetes Namespace & Secrets

Create a dedicated namespace for Jira:
```bash
kubectl create namespace jira
```

Create a Kubernetes Secret storing your database credentials so they are never hard-coded in plain text:
```bash
kubectl create secret generic jira-db-secret \
  --namespace jira \
  --from-literal=username=postgres \
  --from-literal=password="$DB_PASSWORD"
```

---

## 4. Verify EFS StorageClass for Shared Home

Jira Data Center requires **Shared Home** to run across all cluster pods using `ReadWriteMany` (RWX) volume mounts.

> [!NOTE]
> **Automatically Deployed by Terraform**: The `efs-sc` StorageClass is now managed directly by Terraform (`kubernetes_storage_class_v1.efs_sc` in [main.tf](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/main.tf)) with your EFS File System ID automatically injected. You do **not** need to create or apply YAML manually!

### Verify the StorageClass in your cluster:
```bash
kubectl get sc efs-sc
```
Expected output:
```text
NAME     PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
efs-sc   efs.csi.aws.com   Delete          Immediate           true                   5m
```

### Inspect the StorageClass parameters:
```bash
kubectl describe sc efs-sc
```
Verify that `fileSystemId` points to your active EFS volume:
```text
Name:                  efs-sc
Provisioner:           efs.csi.aws.com
Parameters:            directoryPerms=700,fileSystemId=fs-09205c11977baaf08,provisioningMode=efs-ap
AllowVolumeExpansion:  True
ReclaimPolicy:         Delete
VolumeBindingMode:     Immediate
```

*(Reference only: Under the hood, Terraform creates the equivalent of:)*
```yaml
# Equivalent manifest managed declaratively in main.tf:
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: <DYNAMICALLY_INJECTED_BY_TERRAFORM>
  directoryPerms: "700"
```

---

## 5. Prepare `jira-values.yaml`

Create your custom values file for the official Atlassian Jira Data Center Helm chart.

```yaml
# jira-values.yaml
replicaCount: 2

jira:
  service:
    type: ClusterIP
    port: 80

  resources:
    container:
      requests:
        cpu: "2"
        memory: "6Gi"
      limits:
        cpu: "3"
        memory: "10Gi"
    jvm:
      minHeap: "4g"
      maxHeap: "6g"

  # Database configuration pointing to Aurora PostgreSQL
  database:
    type: postgres72
    url: "jdbc:postgresql://<REPLACE_WITH_RDS_CLUSTER_ENDPOINT>:5432/jiradb"
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
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    # Sticky Sessions (Mandatory for Jira Data Center clustering)
    alb.ingress.kubernetes.io/affinity: cookie
    alb.ingress.kubernetes.io/affinity-mode: persistent
    alb.ingress.kubernetes.io/session-cookie-name: AWSALB
    alb.ingress.kubernetes.io/session-cookie-expires: "86400"
  host: ""
  path: "/"
```

> **Placeholders to replace:**
> 1. `<REPLACE_WITH_RDS_CLUSTER_ENDPOINT>`: Run `terraform output -raw rds_cluster_endpoint`
> 2. Optional: If you have an ACM SSL certificate for HTTPS, add:
>    ```yaml
>    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
>    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:xxx:certificate/xxx
>    alb.ingress.kubernetes.io/ssl-redirect: '443'
>    ```

---

## 6. Install Jira Data Center via Helm

### 6.1 Add the Atlassian Helm Repository
```bash
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
helm repo update
```

### 6.2 Deploy Jira
```bash
helm install jira atlassian-data-center/jira \
  --namespace jira \
  -f jira-values.yaml
```

---

## 7. Monitor & Verify Deployment

### 7.1 Check Pod Status
```bash
kubectl get pods -n jira -w
```
Wait until both `jira-0` and `jira-1` pods transition to `Running` and `1/1 Ready`.

### 7.2 Check Shared Storage Mounting
```bash
kubectl describe pod jira-0 -n jira | grep -A 5 -i "Mounts:"
```

### 7.3 Get the Application Load Balancer URL
Check the Ingress resource provisioned by the AWS Load Balancer Controller:
```bash
kubectl get ingress -n jira
```

Under the `ADDRESS` column, you will see the generated AWS ALB DNS name:
```text
NAME   CLASS   HOSTS   ADDRESS                                                                  PORTS   AGE
jira   alb     *       k8s-jira-jira-xxxxxxxxxx-xxxxxxxxxx.us-east-1.elb.amazonaws.com          80      2m
```

Open this address in your web browser to access the **Jira Data Center Setup Wizard**!

---

## 8. Troubleshooting Checklist

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Pod stuck in `ContainerCreating` on volume mount | EFS Security Group not allowing port 2049 | Verify EFS mount targets have `efs-sg` attached (already configured in Terraform). |
| Ingress has no `ADDRESS` | ALB Controller failed to assume role or missing permissions | Verify controller pod logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`. |
| DB Connection Timeout | Pods unable to reach RDS on port 5432 | Verify RDS Security group allows traffic from `10.0.0.0/16` (already configured in `security/`). |
| Pod crashing with `OOMKilled` | Node or container heap limit exceeded | Verify worker nodes are `m5.xlarge` with sufficient JVM heap allocated. |

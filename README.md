# Jira Data Center on AWS EKS & RDS Setup

Production-ready infrastructure architecture for deploying **Atlassian Jira Data Center** on **Amazon Elastic Kubernetes Service (EKS)** with **Amazon Aurora Serverless v2 PostgreSQL** and **Amazon EFS**.

---

## 1. Architecture Overview

Jira Data Center is an enterprise multi-node clustered application designed for high availability, fault tolerance, and load distribution. Unlike Jira Server, all cluster nodes (pods) run concurrently, requiring a shared relational database, shared file storage (`ReadWriteMany`), local block storage for indexing (`ReadWriteOnce`), and an Application Load Balancer with cookie-based sticky sessions.

### Architecture Diagram

```mermaid
flowchart TD
    subgraph Internet ["Internet / Corporate Network"]
        Users(["End Users and Browser Traffic"])
    end

    subgraph AWS_Cloud ["AWS Cloud - VPC 10.0.0.0/16"]
        subgraph Public_Subnets ["Public Subnets - 3 AZs - Tag: kubernetes.io/role/elb=1"]
            IGW["Internet Gateway"]
            NAT["NAT Gateway - Outbound Internet for Nodes"]
            ALB["AWS Application Load Balancer\nManaged by AWS Load Balancer Controller"]
        end

        subgraph Private_Subnets ["Private Subnets - 3 AZs - Tag: kubernetes.io/role/internal-elb=1"]
            subgraph EKS_Cluster ["Amazon EKS Cluster - Control Plane v1.31"]
                OIDC["IAM OIDC Identity Provider - IRSA\nModule: oidc"]

                subgraph EKS_Nodes ["EKS Managed Node Group - 2x m5.xlarge - 4 vCPU, 16 GB RAM, 50 GB Disk"]
                    subgraph Pod1 ["Jira DC Pod 1"]
                        JiraCore1["Jira Application Core\nJVM Heap: 4-8 GB"]
                        EBS1[("Local Home - EBS gp3\nReadWriteOnce RWO\nCaches, Search Index, Logs")]
                        JiraCore1 --- EBS1
                    end

                    subgraph Pod2 ["Jira DC Pod 2"]
                        JiraCore2["Jira Application Core\nJVM Heap: 4-8 GB"]
                        EBS2[("Local Home - EBS gp3\nReadWriteOnce RWO\nCaches, Search Index, Logs")]
                        JiraCore2 --- EBS2
                    end
                end
            end

            subgraph Storage_Backend ["Persistent Backend Services"]
                RDS[("Amazon Aurora Serverless v2\nPostgreSQL v16.1\nIssues, Workflows, Users, Settings\nSecurity Group: Port 5432 from VPC")]
                EFS[("Amazon EFS Shared File System\n1x Regional EFS + 3x Mount Targets\nShared Home: ReadWriteMany RWX\nAttachments, Plugins, Avatars, Cluster Locks")]
            end
        end
    end

    Users -->|HTTPS Port 443| ALB
    IGW --> NAT
    NAT -.->|Outbound updates and pulls| EKS_Nodes

    ALB -->|Sticky Sessions - Cookie Affinity| JiraCore1
    ALB -->|Sticky Sessions - Cookie Affinity| JiraCore2

    JiraCore1 -->|SQL Port 5432| RDS
    JiraCore2 -->|SQL Port 5432| RDS

    JiraCore1 -->|NFS Port 2049| EFS
    JiraCore2 -->|NFS Port 2049| EFS

    OIDC -.->|Temporary IAM Credentials - IRSA| EKS_Nodes
```

---

## 2. Core Components Deep Dive

### 1. Worker Node Group (`m5.xlarge`) — Configured
* **Configuration**: `instance_types = ["m5.xlarge"]`, `disk_size = 50 GB`, `desired_size = 2` (min: 1, max: 3).
* **Why it matters**:
  * AWS EKS defaults to `t3.medium` (2 vCPUs, 4 GB RAM) if unspecified, which causes immediate pod crashes (**`OOMKilled`**) because Jira DC requires **4 GB to 8+ GB of RAM (Heap)** just for the JVM, plus system reserves for Kubernetes daemons (`kubelet`, `aws-node`, `coredns`).
  * `m5.xlarge` provides **4 vCPUs and 16 GiB RAM**, offering ample capacity for Jira's Lucene indexing, caches, and multiple cluster nodes.

### 2. Database: Amazon Aurora Serverless v2 PostgreSQL — Configured
* **Configuration**: PostgreSQL engine `16.1`, Serverless v2 capacity (`min: 0.5 ACU`, `max: 1.0 ACU`), `manage_master_user_password = true` (AWS Secrets Manager integration), and dedicated DB Subnet Group across private subnets.
* **Why it matters**:
  * Jira Data Center does not include an embedded database for production; all cluster nodes connect to the same central database.
  * Aurora Serverless v2 instantly scales compute capacity up and down without downtime and provides automated Multi-AZ replication.
  * Password credentials are securely generated and rotated by AWS Secrets Manager rather than plaintext in code.

### 3. Database Security Group (`security/` module) — Configured
* **Configuration**: `aws_security_group.rds_sg` with `ingress` on TCP port `5432` restricted to `var.vpc_cidr` (`10.0.0.0/16`), and stateful egress.
* **Why it matters**:
  * Prevents unauthorized access while ensuring all worker nodes inside the VPC private subnets can communicate with the Aurora database cluster endpoint.

### 4. Storage Architecture: Local Home vs. Shared Home
Jira Data Center strictly separates local instance data from cluster-shared data:

| Storage Type | Mount Path | AWS Service | Access Mode | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Local Home** | `/var/atlassian/application-data/jira` | **AWS EBS (gp3)** | `ReadWriteOnce` (RWO) | Node-specific Lucene search index, caches, JVM process logs. Fast block I/O. |
| **Shared Home** | `/var/atlassian/application-data/jira/shared` | **AWS EFS** | `ReadWriteMany` (RWX) | Shared files: attachments, avatars, installed plugins, and cluster lock files. |

#### Shared File System: Amazon EFS (`efs/` module) — Configured
* **Configuration**: 
  * `aws_efs_file_system`: Created once as a regional, serverless storage volume.
  * `aws_efs_mount_target`: Created 3 times (`count = 3`), placing one mount target ENI in each private subnet across all 3 Availability Zones (`us-east-1a`, `us-east-1b`, `us-east-1c`).
* **Why one mount target per AZ?**:
  * AWS enforces at most one mount target per AZ.
  * Worker nodes mount EFS locally in their own AZ over NFS (port 2049), ensuring ultra-low latency and avoiding cross-AZ data transfer costs.

#### What are CSI Drivers?
Kubernetes pods cannot natively provision AWS disks without CSI (Container Storage Interface) "drivers":
* **AWS EBS CSI Driver**: Automatically provisions and attaches EBS volumes when Jira requests local storage.
* **AWS EFS CSI Driver**: Automatically mounts the AWS EFS file system when Jira requests `ReadWriteMany` shared storage.

### 5. IAM OIDC Provider (`oidc/` module) — Configured
* **Configuration**: 
  * `aws_iam_openid_connect_provider` registered with the EKS cluster's issuer URL (`module.eks.oidc_url`).
  * `client_id_list = ["sts.amazonaws.com"]`
  * Dynamic TLS thumbprint retrieval via `data "tls_certificate"`.
* **Why it matters**:
  * Establishes cryptographic federated trust between EKS and AWS IAM.
  * Enables **IRSA (IAM Roles for Service Accounts)** so that pods (e.g. EBS CSI driver, EFS CSI driver, AWS Load Balancer Controller) receive temporary scoped AWS credentials.
  * Prevents pods from inheriting full node-level IAM credentials via IMDS (least privilege).

### 6. Ingress & AWS Load Balancer Controller (ALB) — Configured
* **What it does**: Manages an external Application Load Balancer to direct traffic to Jira pods running in private subnets.
* **Sticky Sessions**: In Jira Data Center, user sessions must stick to the same node for consecutive requests (cookie affinity) to prevent session loss or state desynchronization. The ALB handles this automatically.
* **Implementation**: Deployed via `helm_release` (`aws-load-balancer-controller` chart from `https://aws.github.io/eks-charts`) with IRSA annotation on its `ServiceAccount` pointing to `aws_iam_role.alb_controller_role`.
* **Helm Provider v3 Note**: The `set {}` nested block syntax was removed in Helm provider `~> 3.0`. Chart values are now supplied via `values = [ yamlencode({...}) ]`, which also handles nested keys (e.g. `serviceAccount.annotations`) more cleanly.

### 7. Subnet Discovery Tags
Subnets must be tagged so Kubernetes controllers know how to route infrastructure:
* **Public Subnets**: `kubernetes.io/role/elb = "1"` (Tells AWS Load Balancer Controller where to deploy public ALBs).
* **Private Subnets**: `kubernetes.io/role/internal-elb = "1"` (For internal load balancers).

---

## 3. Jira DC Helm Chart Readiness Checklist

| Requirement | Description | Status | Next Steps |
| :---: | :--- | :---: | :--- |
| **VPC & Networking** | 3 Public Subnets, 3 Private Subnets, IGW, NAT GW + ALB Tags | ✅ Ready | - |
| **DB Subnet Group** | DB Subnet Group across private subnets | ✅ Ready | - |
| **Database Security** | Security group allowing TCP 5432 from VPC | ✅ Ready | - |
| **Aurora PostgreSQL** | Aurora Serverless v2 PostgreSQL v16.1 cluster | ✅ Ready | - |
| **EKS Control Plane** | AWS EKS Cluster v1.31 | ✅ Ready | - |
| **Node Group Sizing** | 2x `m5.xlarge` (16 GB RAM, 50 GB disk) | ✅ Ready | - |
| **EKS OIDC Provider** | IAM OIDC provider for IRSA (`oidc/` module) | ✅ Ready | - |
| **AWS EFS File System** | 1x EFS + 3x Mount Targets in private subnets (`efs/`) | ✅ Ready | - |
| **EBS CSI Driver** | EKS Add-on + IRSA IAM Role for `jira-local-home` | ✅ Ready | - |
| **EFS CSI Driver** | EKS Add-on + IRSA IAM Role + EFS SG for `jira-shared-home` | ✅ Ready | - |
| **Ingress & ALB** | AWS Load Balancer Controller via Helm + IRSA role & policy | ✅ Ready | - |

> 🚀 **Jira Installation Guide**: For exact instructions, database connection details, and `values.yaml` configuration to install the Jira Data Center Helm chart, see [JIRA_HELM_INSTALLATION_GUIDE.md](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/JIRA_HELM_INSTALLATION_GUIDE.md).
>
> 📖 **Deep Dive Documentation**: For an in-depth explanation of how EKS IAM (OIDC/IRSA), ServiceAccounts, EBS CSI, and EFS Mount Targets work under the hood, see [EKS_STORAGE_AND_IAM_DEEP_DIVE.md](file:///e:/GitRepos/interview/jira-dc-eks-rds-setup/EKS_STORAGE_AND_IAM_DEEP_DIVE.md).

---

## 4. Repository Structure

```text
jira-dc-eks-rds-setup/
├── README.md                       # Infrastructure documentation and architecture diagram
├── JIRA_HELM_INSTALLATION_GUIDE.md # Step-by-step Jira DC Helm chart installation guide
├── main.tf                         # Root Terraform orchestrator (EKS, Add-ons, ALB Controller)
├── output.tf                       # Root outputs (endpoints, cluster name, secrets, EFS ID)
├── variables.tf                    # Root input variables
├── provider.tf                     # AWS, Kubernetes (exec auth), Helm provider configuration
├── alb_iam_policy.json             # Official AWS Load Balancer Controller IAM policy
├── locals.tf                       # Local variables and naming conventions
├── env/
│   └── dev/
│       ├── terraform.tfvars        # Dev environment variables
│       └── backend.tfvars   # S3 / DynamoDB remote state backend config
├── vpc/                    # VPC module (subnets, IGW, NAT GW, DB subnet group)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
├── iam/                    # IAM module (EKS cluster role, node group role)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
├── security/               # Security module (RDS port 5432 security group & rules)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
├── rds/                    # Database module (Aurora Serverless v2 PostgreSQL v16.1)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
├── eks/                    # EKS module (Cluster, Node Group: m5.xlarge, 50GB; outputs: endpoint, CA, name)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
├── oidc/                   # IAM OIDC Provider module for IRSA
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
└── efs/                    # Amazon EFS shared storage module (1x EFS + 3x Mount Targets)
    ├── main.tf
    ├── variables.tf
    └── output.tf
```

---

## 5. Usage & Deployment

### 1. Initialize Terraform with Backend
```bash
terraform init -backend-config="env/dev/backend.tfvars"
```

### 2. Validate Configuration
```bash
terraform validate
```

### 3. Review Execution Plan
```bash
terraform plan -var-file="env/dev/terraform.tfvars"
```

### 4. Deploy Infrastructure
```bash
terraform apply -var-file="env/dev/terraform.tfvars"
```

---

## 6. Known Issues & Fixes Applied

### Helm Provider v3 — `set {}` block removed
The `helm_release` resource no longer supports nested `set {}` blocks in Helm provider `~> 3.0`. All chart values must be supplied via the `values` argument using a YAML string.

**Before (v2, broken):**
```hcl
set {
  name  = "clusterName"
  value = "my-cluster"
}
```
**After (v3, correct):**
```hcl
values = [
  yamlencode({
    clusterName    = "my-cluster"
    serviceAccount = { create = true, name = "aws-load-balancer-controller" }
  })
]
```

### Provider Chicken-and-Egg — EKS cluster not yet created at plan time
The `kubernetes` provider originally used `data "aws_eks_cluster"` to fetch the cluster endpoint. This caused a hard failure during the first `terraform plan` because the cluster didn't exist yet.

**Fix**: The `kubernetes` provider now references `module.eks.*` outputs (resolved post-creation) and uses an `exec` block to fetch a fresh token via the AWS CLI — avoiding static token expiry during long applies:

```hcl
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
```

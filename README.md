# Jira Data Center on AWS EKS & RDS Setup

Production-ready infrastructure architecture for deploying **Atlassian Jira Data Center** on **Amazon Elastic Kubernetes Service (EKS)** with **Amazon Aurora Serverless v2 PostgreSQL** and **Amazon EFS**.

---

## 1. Architecture Overview

Jira Data Center is an enterprise multi-node clustered application designed for high availability, fault tolerance, and load distribution. Unlike Jira Server, all cluster nodes (pods) run concurrently, requiring a shared relational database, shared file storage (`ReadWriteMany`), local block storage for indexing (`ReadWriteOnce`), and an Application Load Balancer with cookie-based sticky sessions.

### Architecture Diagram

```mermaid
flowchart TD
    subgraph Internet ["Internet / Corporate Network"]
        Users(["End Users & Browser Traffic"])
    end

    subgraph AWS_Cloud ["AWS Cloud (VPC: 10.0.0.0/16)"]
        subgraph Public_Subnets ["Public Subnets (3 AZs) - Tag: kubernetes.io/role/elb=1"]
            IGW["Internet Gateway"]
            NAT["NAT Gateway (Outbound Internet for Nodes)"]
            ALB["AWS Application Load Balancer (ALB)\n(Managed by AWS Load Balancer Controller)"]
        end

        subgraph Private_Subnets ["Private Subnets (3 AZs) - Tag: kubernetes.io/role/internal-elb=1"]
            subgraph EKS_Cluster ["Amazon EKS Cluster (Control Plane v1.31)"]
                OIDC["IAM OIDC Identity Provider (IRSA)\n[Module: oidc]"]

                subgraph EKS_Nodes ["EKS Managed Node Group (2x m5.xlarge - 4 vCPU, 16 GB RAM, 50 GB Disk)"]
                    subgraph Pod1 ["Jira DC Pod 1"]
                        JiraCore1["Jira Application Core\n(JVM Heap: 4-8 GB)"]
                        EBS1[("Local Home (EBS gp3)\nReadWriteOnce (RWO)\nCaches, Search Index, Logs")]
                        JiraCore1 --- EBS1
                    end

                    subgraph Pod2 ["Jira DC Pod 2"]
                        JiraCore2["Jira Application Core\n(JVM Heap: 4-8 GB)"]
                        EBS2[("Local Home (EBS gp3)\nReadWriteOnce (RWO)\nCaches, Search Index, Logs")]
                        JiraCore2 --- EBS2
                    end
                end
            end

            subgraph Storage_Backend ["Persistent Backend Services"]
                RDS[("Amazon Aurora Serverless v2 PostgreSQL v16.1\n(Issues, Workflows, Users, Settings)\n[Security Group: Port 5432 from VPC]")]
                EFS[("AWS EFS Network File System\nShared Home: ReadWriteMany (RWX)\n(Attachments, Plugins, Avatars, Cluster Locks)")]
            end
        end
    end

    Users -->|HTTPS / Port 443| ALB
    IGW --> NAT
    NAT -.->|Outbound updates/pulls| EKS_Nodes

    ALB -->|Sticky Sessions: Cookie Affinity| JiraCore1
    ALB -->|Sticky Sessions: Cookie Affinity| JiraCore2

    JiraCore1 -->|SQL / Port 5432| RDS
    JiraCore2 -->|SQL / Port 5432| RDS

    JiraCore1 -->|NFS / Port 2049| EFS
    JiraCore2 -->|NFS / Port 2049| EFS

    OIDC -.->|Temporary IAM Credentials (IRSA)| EKS_Nodes
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

### 6. Ingress & AWS Load Balancer Controller (ALB)
* **What it does**: Manages an external Application Load Balancer to direct traffic to Jira pods running in private subnets.
* **Sticky Sessions**: In Jira Data Center, user sessions must stick to the same node for consecutive requests (cookie affinity) to prevent session loss or state desynchronization. The ALB handles this automatically.

### 7. Subnet Discovery Tags
Subnets must be tagged so Kubernetes controllers know how to route infrastructure:
* **Public Subnets**: `kubernetes.io/role/elb = "1"` (Tells AWS Load Balancer Controller where to deploy public ALBs).
* **Private Subnets**: `kubernetes.io/role/internal-elb = "1"` (For internal load balancers).

---

## 3. Jira DC Helm Chart Readiness Checklist

| Requirement | Description | Status | Next Steps |
| :---: | :--- | :---: | :--- |
| **VPC & Networking** | 3 Public Subnets, 3 Private Subnets, IGW, NAT GW | ✅ Ready | Add ALB discovery tags |
| **DB Subnet Group** | DB Subnet Group across private subnets | ✅ Ready | - |
| **Database Security** | Security group allowing TCP 5432 from VPC | ✅ Ready | - |
| **Aurora PostgreSQL** | Aurora Serverless v2 PostgreSQL v16.1 cluster | ✅ Ready | - |
| **EKS Control Plane** | AWS EKS Cluster v1.31 | ✅ Ready | - |
| **Node Group Sizing** | 2x `m5.xlarge` (16 GB RAM, 50 GB disk) | ✅ Ready | - |
| **EKS OIDC Provider** | IAM OIDC provider for IRSA (`oidc/` module) | ✅ Ready | - |
| **EBS CSI Driver** | Dynamic volume provisioning for `jira-local-home` | ⏳ Pending | Add `aws-ebs-csi-driver` EKS add-on + IAM role |
| **AWS EFS + EFS CSI** | Shared storage for `jira-shared-home` | ⏳ Pending | Create EFS file system + install EFS CSI driver |
| **Ingress & ALB** | Expose web UI with cookie sticky sessions | ⏳ Pending | Deploy AWS Load Balancer Controller |

---

## 4. Repository Structure

```text
jira-dc-eks-rds-setup/
├── README.md               # Infrastructure documentation and architecture diagram
├── main.tf                 # Root Terraform orchestrator
├── variables.tf            # Root input variables
├── provider.tf             # AWS provider configuration
├── locals.tf               # Local variables and naming conventions
├── env/
│   └── dev/
│       ├── terraform.tfvars # Dev environment variables
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
├── eks/                    # EKS module (Cluster, Node Group: m5.xlarge, 50GB, OIDC output)
│   ├── main.tf
│   ├── variables.tf
│   └── output.tf
└── oidc/                   # IAM OIDC Provider module for IRSA
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

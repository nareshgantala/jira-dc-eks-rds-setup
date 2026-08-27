# Infrastructure Components Catalog (One-Liners)

A complete architectural reference defining every single component created in this **Jira Data Center on AWS EKS & Aurora PostgreSQL** infrastructure with a concise, punchy one-line definition.

---

## 1. Networking & VPC (`vpc/` module)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_vpc.main`** | VPC | The isolated virtual cloud network (`10.0.0.0/16`) housing all Jira Data Center compute, database, and storage assets. |
| **`aws_internet_gateway.gw`** | Gateway | The VPC edge gateway enabling bidirectional Internet communication for public subnets and the Application Load Balancer. |
| **`aws_subnet.public_subnet`** | Subnet (x3) | Three public subnets across 3 AZs with auto-assigned public IPs hosting the Internet-facing ALB, NAT Gateway, and ingress entry points (`kubernetes.io/role/elb=1`). |
| **`aws_subnet.private_subnet`** | Subnet (x3) | Three isolated subnets across 3 AZs hosting EKS worker nodes, RDS PostgreSQL, and EFS mount targets with zero direct Internet ingress (`kubernetes.io/role/internal-elb=1`). |
| **`aws_eip.nat`** | Elastic IP | A static public IPv4 address permanently allocated to the NAT Gateway for predictable egress routing. |
| **`aws_nat_gateway.nat`** | NAT Gateway | A managed outbound translation gateway allowing private subnet resources (nodes and pods) to pull container images, OS patches, and Atlassian plugins without exposing private IPs. |
| **`aws_route_table.public_rt`** | Route Table | Directs outbound public subnet traffic (`0.0.0.0/0`) directly through the Internet Gateway. |
| **`aws_route_table.private_rt`** | Route Table | Directs outbound private subnet internet traffic (`0.0.0.0/0`) through the NAT Gateway. |
| **`aws_route_table_association.public`** | Association (x3) | Binds all 3 public subnets to the public route table. |
| **`aws_route_table_association.private`** | Association (x3) | Binds all 3 private subnets to the private route table. |
| **`aws_db_subnet_group.jira_dc_db_subnet_group`** | DB Subnet Group | Designates the 3 private subnets across multiple AZs as the deployment zones for the Aurora PostgreSQL cluster. |

---

## 2. Security & Firewall Rules (`security/` module)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_security_group.rds_sg`** | Security Group | Firewall protecting PostgreSQL database instances by permitting TCP traffic on port `5432` exclusively from within the VPC CIDR (`10.0.0.0/16`). |
| **`aws_security_group.efs_sg`** | Security Group | Firewall protecting EFS network interfaces by permitting NFS traffic on port `2049` exclusively from within the VPC CIDR. |

---

## 3. IAM & Identity (`iam/` & `oidc/` modules)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_iam_role.eks_role`** | IAM Role | Assumed by the AWS EKS control plane service to manage AWS infrastructure (ENIs, load balancers) on behalf of the cluster. |
| **`AmazonEKSClusterPolicy`** | Policy Attachment | Grants the EKS control plane full rights to manage Kubernetes cluster networking and compute dependencies. |
| **`aws_iam_role.node_group_role`** | IAM Role | Assumed by EC2 worker node instances to join the EKS cluster, communicate with the control plane, and pull container images. |
| **`AmazonEKSWorkerNodePolicy`** | Policy Attachment | Grants worker nodes permission to register with the EKS cluster and manage node life cycles. |
| **`AmazonEKS_CNI_Policy`** | Policy Attachment | Grants the AWS VPC CNI plugin (`aws-node`) authority to modify IP addresses and elastic network interfaces on EC2 nodes. |
| **`AmazonEC2ContainerRegistryReadOnly`** | Policy Attachment | Allows worker node kubelets to pull private and public container images from Amazon ECR. |
| **`aws_iam_openid_connect_provider.eks_oidc`** | OIDC Provider | Cryptographic federated bridge between EKS and AWS IAM enabling IRSA (IAM Roles for Service Accounts) so pods receive temporary scoped AWS credentials without hardcoded keys. |

---

## 4. Kubernetes Compute: EKS Cluster & Nodes (`eks/` module)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_eks_cluster.jira_dc_cluster`** | EKS Cluster | AWS-managed, highly available Kubernetes control plane running v1.31 with API authentication mode. |
| **`aws_eks_node_group.example`** | Managed Node Group | Auto-scaling pool of 2x `m5.xlarge` EC2 instances (4 vCPUs, 16 GiB RAM, 50 GB disk) in private subnets sized specifically to handle Jira DC JVM heap memory requirements. |

---

## 5. Relational Database: Aurora PostgreSQL Serverless v2 (`rds/` module)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_rds_cluster.jira_dc_rds_cluster`** | Aurora Cluster | Highly available, multi-AZ PostgreSQL 16.8 database cluster storing all relational Jira Data Center entities (issues, workflows, comments, users, and audit logs). |
| **`aws_rds_cluster_instance.jira_dc_rds_instance`** | Aurora Instance | Serverless v2 compute instance dynamically scaling capacity between 0.5 and 1.0 ACUs (Aurora Capacity Units) based on Jira application workload. |
| **`AWS Secrets Manager (Master Credentials)`** | Secret | AWS-managed encrypted credential store automatically provisioning and rotating the master database password (`jiraadmin`). |

---

## 6. Shared Storage: Amazon EFS (`efs/` module)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_efs_file_system.jira_dc_efs`** | File System | Elastic, serverless NFS file system providing `ReadWriteMany` (RWX) shared storage for Jira attachments, avatars, installed plugins, and cluster lock files. |
| **`aws_efs_mount_target.jira_dc_efs_mount`** | Mount Target (x3) | Network interfaces placed in each private subnet across all 3 AZs providing local, low-latency, cross-AZ-cost-free NFS access on port 2049. |

---

## 7. Storage Drivers & IRSA Roles (Root `main.tf`)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_iam_role.ebs_csi_role`** | IAM Role (IRSA) | Role assumed by the EBS CSI controller pod via OIDC web identity token federation (`kube-system:ebs-csi-controller-sa`). |
| **`AmazonEBSCSIDriverPolicy`** | Policy Attachment | Grants EBS CSI driver permissions to create, attach, detach, and delete AWS EBS `gp3` volumes dynamically. |
| **`aws_eks_addon.ebs_csi`** | EKS Add-on | In-cluster storage driver managing `gp3` block storage volumes for Jira Data Center local home directories (`ReadWriteOnce` — search indexes, caches, and logs). |
| **`aws_iam_role.efs_csi_role`** | IAM Role (IRSA) | Role assumed by the EFS CSI controller pod via OIDC web identity token federation (`kube-system:efs-csi-controller-sa`). |
| **`AmazonEFSCSIDriverPolicy`** | Policy Attachment | Grants EFS CSI driver permissions to create EFS access points and authorize pod NFS client mounts. |
| **`aws_eks_addon.efs_csi`** | EKS Add-on | In-cluster storage driver managing concurrent NFS mounts into Jira Data Center application pods for shared home directories (`ReadWriteMany`). |

---

## 8. Ingress, Load Balancing & Kubernetes Storage (Root `main.tf`)

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws_iam_role.alb_controller_role`** | IAM Role (IRSA) | Role assumed by the AWS Load Balancer Controller pod via OIDC web identity token federation (`kube-system:aws-load-balancer-controller`). |
| **`aws_iam_policy.alb_controller_policy`** | IAM Policy | Official AWS ELBv2 policy (`alb_iam_policy.json`) authorizing full management of Application Load Balancers, Target Groups, and Listener Rules. |
| **`aws_iam_role_policy_attachment.alb_controller_policy_attach`** | Policy Attachment | Binds the ALB controller policy to `aws_iam_role.alb_controller_role`. |
| **`helm_release.alb_controller`** | Helm Release | Deploys `aws-load-balancer-controller` (v3.5.0) in `kube-system`, pre-configured with cluster name, region (`us-east-1`), and VPC ID to bypass IMDSv2 hop limit timeouts. |
| **`kubernetes_storage_class_v1.efs_sc`** | StorageClass | Kubernetes storage class (`efs-sc`) provisioned via Terraform that dynamically binds the EFS File System ID for instant automated PVC provisioning with POSIX 700 permissions. |

---

## 9. Core In-Cluster DaemonSets & Controllers

| Component / Resource | Type | One-Line Definition |
| :--- | :--- | :--- |
| **`aws-node` (AWS VPC CNI)** | DaemonSet | Assigns genuine, routable AWS VPC private IP addresses directly from private subnets to every pod on each worker node. |
| **`kube-proxy`** | DaemonSet | Manages IP translation and TCP/UDP packet forwarding rules on each worker node for Kubernetes ClusterIP and NodePort services. |
| **`coredns`** | Deployment | Scalable in-cluster DNS service providing internal service name resolution (e.g. `jira.jira.svc.cluster.local`) across all namespaces. |
| **`alb` (IngressClass)** | IngressClass | The cluster-wide ingress class that registers the AWS Load Balancer Controller to dynamically provision internet-facing ALBs with cookie-based session affinity upon detecting Ingress manifests. |

---

## Summary Matrix: How They Work Together

```text
[Internet Users]
       │
       ▼ (HTTPS 443)
[AWS Application Load Balancer] (Managed by: aws-load-balancer-controller + alb-controller-role via IRSA)
       │ (Cookie Sticky Session Affinity: AWSALB)
       ├───────────────────────────────┐
       ▼                               ▼
[Jira DC Pod 1]                [Jira DC Pod 2] (Running on: m5.xlarge EKS Nodes inside Private Subnets)
   │           │                  │           │
   │ (gp3)     │ (NFS 2049)       │ (gp3)     │ (NFS 2049)
   ▼           ▼                  ▼           ▼
[EBS Volume] [EFS Shared Home] [EBS Volume] [EFS Shared Home]
(ebs-csi)    (efs-csi + efs-sc) (ebs-csi)   (efs-csi + efs-sc)
       │                                       │
       └───────────────────┬───────────────────┘
                           ▼ (SQL Port 5432)
       [Amazon Aurora Serverless v2 PostgreSQL] (Protected by rds_sg)
```

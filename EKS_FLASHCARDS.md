# ☸️ Amazon EKS Revision Flashcards: Architecture, Security & IAM

> **Format:** Front (Question / Scenario) ⇄ Back (Answer / Solution)  
> **How to import into Google Docs:** Open Google Drive → Click **New** → **File Upload** → Select this markdown file (or open in Google Docs directly / copy & paste).

---

## 🎴 Flashcard 1: EKS Cluster Role vs Node Group Role

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What is the fundamental difference between the **EKS Cluster IAM Role** and the **EKS Node Group IAM Role**? |
| **BACK (Answer)** | • **EKS Cluster Role (`aws_eks_cluster.role_arn`):**<br>  - **Who assumes it:** The AWS-managed **Control Plane** (`eks.amazonaws.com`).<br>  - **Purpose:** Allows Kubernetes control plane components (API server, controller manager) to manage AWS resources (create cross-account ENIs, manage security groups, talk to ELBs).<br><br>• **EKS Node Group Role (`aws_eks_node_group.node_role_arn`):**<br>  - **Who assumes it:** The **EC2 Worker Node instances** (`ec2.amazonaws.com`).<br>  - **Purpose:** Allows worker nodes to register with the EKS cluster, configure pod networking (VPC CNI), and pull container images from Amazon ECR. |

---

## 🎴 Flashcard 2: Mandatory Policy for EKS Control Plane

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Which AWS managed policy is strictly required for the EKS Cluster Role, and what does it grant? |
| **BACK (Answer)** | **`AmazonEKSClusterPolicy`**<br><br>• **What it grants:** Provides the Kubernetes control plane with permissions to create and manage AWS resources on your behalf, including:<br>  - Elastic Network Interfaces (ENIs) attached to your VPC subnets for control plane-to-node communication.<br>  - Security groups and route table interactions.<br>  - Classic and Application Load Balancer discovery/management. |

---

## 🎴 Flashcard 3: The 3 Mandatory Policies for EKS Worker Nodes

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What are the 3 mandatory AWS managed policies required on an EKS Node Group IAM Role, and what is the role of each? |
| **BACK (Answer)** | **1. `AmazonEKSWorkerNodePolicy`:**<br>Allows the worker node `kubelet` daemon to communicate with the EKS cluster control plane API.<br><br>**2. `AmazonEKS_CNI_Policy`:**<br>Allows the AWS VPC CNI daemonset (`aws-node`) to allocate and attach secondary ENIs and private IPs to EC2 nodes for Pods.<br><br>**3. `AmazonEC2ContainerRegistryReadOnly`:**<br>Allows nodes to pull container images from private and public Amazon ECR repositories.<br><br>*(Recommended bonus: `AmazonSSMManagedInstanceCore` to securely SSH/SSM into worker nodes without a bastion host).* |

---

## 🎴 Flashcard 4: Terraform IAM Race Condition & `depends_on`

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Why must `aws_eks_cluster` and `aws_eks_node_group` explicitly declare `depends_on` for their `aws_iam_role_policy_attachment` resources? |
| **BACK (Answer)** | • **The Problem:** In AWS IAM, role creation and policy attachment are separate asynchronous API calls. Even if Terraform creates the role, IAM permissions take several seconds to propagate globally.<br><br>• **The Failure:** Without `depends_on`, Terraform starts provisioning the EKS cluster or worker nodes before the IAM policies are active, causing AWS to reject cluster creation with: `ResourceInitializationError` or `UnauthorizedOperation`.<br><br>• **Solution:**<br>```hcl\nresource "aws_eks_cluster" "main" {\n  ...\n  depends_on = [\n    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy\n  ]\n}\n``` |

---

## 🎴 Flashcard 5: EKS VPC Subnet & Multi-AZ Constraints

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What are the minimum subnet and Availability Zone requirements when creating an Amazon EKS cluster? |
| **BACK (Answer)** | • **Minimum AZs:** EKS requires subnets in at least **two different Availability Zones** (AWS best practice is 3 AZs for high availability).<br>• **Subnet Sizes:** Each subnet should have at least a `/28` CIDR block (minimum 16 IPs), but **`/24` (256 IPs) is strongly recommended** because every Pod consumes a real VPC IP address via the AWS VPC CNI.<br>• **Control Plane Placement:** When configuring `vpc_config`, pass subnets across 2 or 3 AZs so EKS can place control plane ENIs redundantly. |

---

## 🎴 Flashcard 6: Node IAM Role vs IRSA / Pod Identity

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Why is attaching application policies (e.g. S3, EFS access for Jira) directly to the Node Group IAM Role considered an anti-pattern? What is the correct alternative? |
| **BACK (Answer)** | • **Anti-pattern Risk:** If you attach S3 or EFS permissions to the Node Group IAM role, **EVERY pod** running on that worker node inherits those permissions, violating the principle of least privilege.<br><br>• **The Modern Solution:** Use **IRSA (IAM Roles for Service Accounts)** or **EKS Pod Identity**:<br>  - Creates an OpenID Connect (OIDC) identity provider for the EKS cluster.<br>  - Assigns specific IAM roles directly to individual Kubernetes `ServiceAccount`s.<br>  - Only the Jira pod gets Jira's permissions; other pods on the same node get nothing. |

---

## 🎴 Flashcard 7: Storage Architecture for Jira Data Center on EKS

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Jira Data Center runs multiple clustered nodes on Kubernetes. What storage types are required for `jira-local-home` vs `jira-shared-home`? |
| **BACK (Answer)** | • **`jira-local-home` (Per Pod):**<br>  - **Storage Type:** Fast block storage via **Amazon EBS** (`gp3`) using `ReadWriteOnce` (RWO) PVCs per Pod.<br>  - **Content:** Lucene search indexes, local logs, and caches specific to that individual node.<br><br>• **`jira-shared-home` (Shared across All Pods):**<br>  - **Storage Type:** Shared distributed filesystem via **Amazon EFS** using `ReadWriteMany` (RWX) PVC with the AWS EFS CSI Driver.<br>  - **Content:** Attachments, avatars, shared plugins, and license data that must be accessible by all Jira cluster nodes simultaneously. |

---

## 🎴 Flashcard 8: Cluster Authentication: `aws-auth` ConfigMap vs EKS Access Entries

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How has Kubernetes authentication in Amazon EKS evolved from the legacy `aws-auth` ConfigMap to EKS Access Entries? |
| **BACK (Answer)** | • **Legacy (`aws-auth` ConfigMap):** Required editing a YAML ConfigMap in the `kube-system` namespace to map IAM ARNs to Kubernetes RBAC groups. Prone to corruption and difficult to manage with Terraform.<br><br>• **Modern (EKS Access Entries - EKS 1.23+):** Managed natively via AWS APIs using `aws_eks_access_entry` and `aws_eks_access_policy_association` in Terraform. No Kubernetes ConfigMap editing required; fully managed at the AWS infrastructure layer. |

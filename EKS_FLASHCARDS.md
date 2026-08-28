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

---

## 🎴 Flashcard 9: The 3 IAM Layers in EKS (Why Cluster & Node Roles Aren't Enough)

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | If we already have an IAM role for the EKS Cluster and an IAM role for the Node Group, why do we still need an OIDC Provider? |
| **BACK (Answer)** | EKS security is divided into **3 separate layers**:<br><br>1. **EKS Cluster Role:** Assumed **only** by the AWS-managed Control Plane (`eks.amazonaws.com`) to manage cross-account ENIs and ELBs. Pods cannot use it.<br><br>2. **Node Group Role (EC2 Instance Profile):** Assumed by the EC2 host OS and `kubelet` to join the cluster, assign VPC IPs via CNI, and pull images from ECR.<br><br>3. **Pod-Level IAM (IRSA via OIDC):** If you attach application policies (e.g., EBS volume creation, EFS mounting, Route53) to the Node Group role, **EVERY pod on that EC2 node inherits those permissions**, creating a major security risk.<br><br>• **Why OIDC is Mandatory:** The OIDC Provider establishes cryptographic federated trust between EKS and AWS IAM, enabling **IRSA (IAM Roles for Service Accounts)** so that only specific, designated pods get granular AWS IAM permissions. |

---

## 🎴 Flashcard 10: How IRSA & OIDC Work Under the Hood (Step-by-Step)

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What is the step-by-step authentication flow of IRSA (IAM Roles for Service Accounts) via OIDC under the hood? |
| **BACK (Answer)** | **1. Projected Token Injection:** Kubernetes automatically projects an OIDC JSON Web Token (JWT) into the pod filesystem at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`.<br><br>**2. SDK Call:** The AWS SDK inside the pod detects the token and calls AWS STS via `sts:AssumeRoleWithWebIdentity`, passing the JWT and the target IAM Role ARN.<br><br>**3. Cryptographic Verification:** AWS STS contacts the cluster's OIDC Provider endpoint to verify the JWT signature against the cluster's public keys.<br><br>**4. Trust Policy Evaluation:** STS checks the IAM Role's trust condition to confirm the token's subject (`sub`) matches the exact `system:serviceaccount:<namespace>:<serviceaccount-name>`.<br><br>**5. Temporary Scoped Credentials:** STS issues short-lived, auto-rotating AWS credentials (AccessKey, SecretKey, SessionToken) strictly to that specific pod.<br><br>• **Key Advantage:** Zero static AWS access keys are ever stored in code, configmaps, or container images. |

---

## 🎴 Flashcard 11: The IMDS Security Vulnerability (Why Pods Shouldn't Inherit Node Roles)

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What is the security vulnerability of letting Pods inherit the EC2 Node Group IAM Role, and how do IMDSv2 and OIDC protect against it? |
| **BACK (Answer)** | • **The Vulnerability:** By default, any container on an EC2 instance can query the EC2 Instance Metadata Service (`http://169.254.169.254/latest/meta-data/iam/security-credentials/`) and steal the node's IAM credentials. If the node role has EBS, EFS, or S3 admin access, any rogue or compromised pod inherits full AWS access to delete or alter backend infrastructure.<br><br>• **Defense 1 - IMDSv2 Hop Limit:** Configure `http_put_response_hop_limit = 1` in the node launch template. Because network packets crossing the container bridge network decrement IP TTL by 1, a hop limit of 1 stops pods from reaching the metadata IP while allowing the host EC2 OS to access it.<br><br>• **Defense 2 - IRSA via OIDC:** Keeps the Node Group IAM Role strictly scoped to base infrastructure (`EKSWorkerNodePolicy`, `CNI_Policy`, `ECRReadOnly`) and delegates all application/controller permissions to individual ServiceAccounts via OIDC. |

---

## 🎴 Flashcard 12: Implementing EKS OIDC Provider & Trust Policy in Terraform

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How do you configure the EKS OIDC Provider in Terraform, and what IAM Trust Policy is required for a Pod's IAM Role? |
| **BACK (Answer)** | **1. Create the OIDC Provider in Terraform:**<br>```hcl\ndata "tls_certificate" "eks" {\n  url = aws_eks_cluster.main.identity[0].oidc[0].issuer\n}\n\nresource "aws_iam_openid_connect_provider" "eks" {\n  client_id_list  = ["sts.amazonaws.com"]\n  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]\n  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer\n}\n```<br>**2. Pod IAM Role Trust Policy:**<br>```hcl\nassume_role_policy = jsonencode({\n  Version = "2012-10-17"\n  Statement = [{\n    Action = "sts:AssumeRoleWithWebIdentity"\n    Effect = "Allow"\n    Principal = {\n      Federated = aws_iam_openid_connect_provider.eks.arn\n    }\n    Condition = {\n      StringEquals = {\n        "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"\n        "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"\n      }\n    }\n  }]\n})\n``` |

---

## 🎴 Flashcard 13: OIDC & IRSA in Practice: Jira Data Center Architecture

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Which specific components in the Jira Data Center on EKS architecture require IRSA via OIDC, and why? |
| **BACK (Answer)** | • **1. AWS EBS CSI Driver (`ebs-csi-controller-sa`):**<br>  - **Policy:** `AmazonEBSCSIDriverPolicy`<br>  - **Purpose:** Dynamically provisions and attaches EBS `gp3` volumes for `jira-local-home` (RWO).<br><br>• **2. AWS EFS CSI Driver (`efs-csi-controller-sa`):**<br>  - **Policy:** `AmazonEFSCSIDriverPolicy`<br>  - **Purpose:** Automatically mounts the shared EFS filesystem for `jira-shared-home` (RWX).<br><br>• **3. AWS Load Balancer Controller (`aws-load-balancer-controller`):**<br>  - **Policy:** `AWSLoadBalancerControllerIAMPolicy`<br>  - **Purpose:** Discovers Ingress resources and automatically provisions the AWS Application Load Balancer (ALB) with cookie-based sticky sessions.<br><br>• **4. Jira Core Application Pods:**<br>  - **Permissions:** **ZERO direct AWS IAM permissions** needed! They only talk to PostgreSQL (RDS) and mounted filesystem paths, following strict Principle of Least Privilege. |

---

## 🎴 Flashcard 14: Ingress Health Check Path vs. Kubernetes Readiness Probe

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How should the AWS ALB Ingress `healthcheck-path` annotation be configured for an application on EKS, and why must it match the Kubernetes `readinessProbe`? |
| **BACK (Answer)** | • **The Golden Rule:** Always configure `alb.ingress.kubernetes.io/healthcheck-path` to match the exact dedicated status endpoint defined in the Pod's **`readinessProbe`** (e.g. `/status` for Jira/Atlassian, `/actuator/health` for Spring Boot, `/-/ready` for Prometheus, `/healthz` for microservices).<br><br>• **Why Root (`/`) is an Anti-Pattern:**<br>  - **Redirect Failures:** Root paths frequently return `302 Found` (redirecting to `/login.jsp` or `/setup`), which triggers a health check failure if the ALB expects `200 OK`.<br>  - **Server Overhead:** Root loads full HTML/CSS/JS, creates sessions, and runs database queries. Pinging `/` every 5–10s across multiple AZs wastes container CPU and memory.<br>  - **Startup Lag:** During container boot, `/` can serve broken UI or 404 while plugins initialize.<br><br>• **Why Synchronization is Critical:** Ensures the AWS ALB only routes public internet traffic to a pod when both Kubernetes and internal application plugins have declared the pod 100% initialized and ready. |

---

## 🎴 Flashcard 15: AWS ALB "Fail-Open" Resilience Mechanism (All Targets Unhealthy)

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What happens when 100% of targets in an AWS ALB Target Group fail health checks? Why does the Web UI still load? |
| **BACK (Answer)** | • **The "Fail-Open" Mechanism:** When **all** registered targets in a Target Group fail health checks (e.g. 1 out of 1 or 2 out of 2 unhealthy), the AWS Application Load Balancer enters a built-in safety fallback mode and **continues routing incoming traffic to all unhealthy targets** rather than returning an immediate `503 Service Temporarily Unavailable`.<br><br>• **Design Rationale:** AWS assumes that if 100% of targets fail, the health check configuration itself (path, timeout, success codes) is likely misconfigured while the backend application is actually operational.<br><br>• **Partial Failure Contrast:** If 1 target is healthy and 1 is unhealthy, ALB immediately blacklists the unhealthy target and sends 100% of traffic to the healthy one.<br><br>• **Control Plane vs Data Plane:** Breaking the Kubernetes AWS Load Balancer Controller (Control Plane) freezes AWS API sync (ingress updates/deletions), but the physical AWS ALB and Target Groups (Data Plane) continue forwarding network packets uninterrupted. |


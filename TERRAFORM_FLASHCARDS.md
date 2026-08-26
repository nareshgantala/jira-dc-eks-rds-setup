# 📚 Terraform Revision Flashcards: Providers & Backend Configuration

> **Format:** Front (Question / Scenario) ⇄ Back (Answer / Solution)  
> **How to import into Google Docs:** Open Google Drive → Click **New** → **File Upload** → Select this markdown file (or open in Google Docs directly / copy & paste).

---

## 🎴 Flashcard 1: `required_providers` vs `provider` Block

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What is the fundamental difference between the `terraform { required_providers { ... } }` block and the `provider "aws" { ... }` block? |
| **BACK (Answer)** | • **`required_providers` (Declaration):** Defines **which plugin binary to download** from the Terraform registry, including provider source (`hashicorp/aws`) and version constraints (`~> 6.0`).<br><br>• **`provider` (Runtime Configuration):** Configures **how the downloaded plugin interacts with the API** (e.g., target `region = "us-east-1"`, AWS credentials, assume role, default tags). |

---

## 🎴 Flashcard 2: Provider Source Address Syntax

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What does `source = "hashicorp/aws"` mean in Terraform, and what is its standard address format? |
| **BACK (Answer)** | It specifies where Terraform fetches the provider plugin from.<br><br>• **Format:** `[<HOSTNAME>/]<NAMESPACE>/<TYPE>`<br>• **Default Hostname:** `registry.terraform.io` (used if omitted)<br>• **Namespace:** `hashicorp` (the publisher/organization)<br>• **Type / Name:** `aws`<br>• **Full URI:** `registry.terraform.io/hashicorp/aws` |

---

## 🎴 Flashcard 3: The Pessimistic Operator (`~>`)

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What does the version constraint `version = "~> 6.0"` mean? How is it different from `~> 6.0.0`? |
| **BACK (Answer)** | • **`~> 6.0`** allows minor and patch updates: `>= 6.0.0, < 7.0.0` (allows `6.1`, `6.25`, but blocks breaking changes in major version `7.0.0`).<br><br>• **`~> 6.0.0`** allows patch-level updates only: `>= 6.0.0, < 6.1.0` (allows `6.0.1`, but blocks `6.1.0`). |

---

## 🎴 Flashcard 4: HCL Syntax & `backend` Block Placement

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Can the `backend "s3"` block be placed inside `required_providers { ... }`? Where must it be located? |
| **BACK (Answer)** | **No.** Nesting `backend` inside `required_providers` causes a syntax error (`Unsupported block type`).<br><br>• `required_providers` and `backend` must be **sibling blocks** directly inside the top-level `terraform { ... }` block.<br>• Only **one** backend block is permitted per root module configuration. |

---

## 🎴 Flashcard 5: S3 State Locking Mechanisms

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How does state locking work for the AWS S3 backend? Is `enable_locking = true` valid syntax? |
| **BACK (Answer)** | • **`enable_locking` is invalid syntax** and not recognized by the S3 backend.<br><br>• **Terraform 1.10+:** Supports native S3 state locking via `use_lockfile = true` (no DynamoDB table needed).<br><br>• **Terraform < 1.10 / Classic:** Requires an Amazon DynamoDB table configured via `dynamodb_table = "<table-name>"`. |

---

## 🎴 Flashcard 6: Why Variables Fail in `backend` Blocks

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Why does Terraform throw an error if you write `key = "jira/${var.env}/terraform.tfstate"` inside a `backend "s3"` block? |
| **BACK (Answer)** | Terraform evaluates and initializes the backend during the **very first phase** of execution, **before** variables, locals, or resource configurations are loaded.<br><br>Because variables do not exist yet when the backend initializes, values must be passed statically or via **Partial Backend Configuration**. |

---

## 🎴 Flashcard 7: Partial Backend Configuration Pattern

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What is "Partial Backend Configuration" and why is it considered an industry best practice? |
| **BACK (Answer)** | • **Definition:** Declaring an empty backend block in the root code (`backend "s3" {}`) and supplying environment-specific values (`bucket`, `key`, `region`) at runtime using an external `.tfvars` file.<br><br>• **Benefit:** Keeps the codebase **DRY and environment-agnostic**, allowing a single codebase to deploy across `dev`, `qa`, `stage`, and `prod` without code duplication. |

---

## 🎴 Flashcard 8: Multi-Environment State Isolation & CLI Commands

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How do you initialize the `dev` environment with partial backend config, and how do you switch to `prod`? |
| **BACK (Answer)** | **1. Initialize `dev`:**<br>```bash\nterraform init -backend-config="env/dev/backend.tfvars"\n```<br><br>**2. Switch to `prod`:**<br>```bash\nterraform init -backend-config="env/prod/backend.tfvars" -reconfigure\n```<br>*(The `-reconfigure` flag instructs Terraform to ignore the cached backend and connect directly to the new state file).* |

---

## 🎴 Flashcard 9: Passing `.tfvars` Files to `terraform plan` / `apply`

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Why did `terraform plan` interactively prompt for `var.project` and `var.env` even though `env/dev/terraform.tfvars` existed? How do you fix it? |
| **BACK (Answer)** | • **Root Cause:** Terraform only auto-loads variable files named `terraform.tfvars` or `*.auto.tfvars` located **directly in the root working directory**. Files inside subfolders (`env/dev/`) are ignored by default.<br><br>• **Solution:** Explicitly pass the file using the `-var-file` flag:<br>```bash\nterraform plan -var-file="env/dev/terraform.tfvars"\n```<br><br>• **Best Practice:** Save the plan file to ensure the exact planned changes are applied:<br>```bash\nterraform plan -var-file="env/dev/terraform.tfvars" -out="dev.tfplan"\nterraform apply "dev.tfplan"\n``` |

---

## 🎴 Flashcard 10: The `cidrsubnet()` Function Math & Octets

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | In `cidrsubnet(var.vpc_cidr, 8, count.index)` with `var.vpc_cidr = "10.0.0.0/16"`, what do the arguments mean, and why does `count.index` change the **3rd octet**? |
| **BACK (Answer)** | • **Syntax:** `cidrsubnet(prefix, newbits, netnum)`<br>  - `prefix`: Base VPC CIDR (`10.0.0.0/16`).<br>  - `newbits`: Additional prefix bits added (`8`). New mask = `16 + 8 = /24`.<br>  - `netnum`: Subnet slice index (`0, 1, 2...`).<br><br>• **Why the 3rd octet changes:**<br>  An IPv4 address has four 8-bit octets: `[1] . [2] . [3] . [4]`.<br>  The base `/16` locks octets 1 and 2 (`10.0`). Adding `8` bits (`newbits = 8`) uses all 8 bits of **Octet 3** for the subnet number. Thus, `netnum` directly equals the 3rd octet:<br>  - `netnum = 0` ➔ `10.0.0.0/24`<br>  - `netnum = 1` ➔ `10.0.1.0/24`<br>  - `netnum = 2` ➔ `10.0.2.0/24` |

---

## 🎴 Flashcard 11: Route Tables: Destination CIDR vs Subnet Associations

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Should you put your public subnet CIDRs inside the `aws_route_table` `route` block? How do subnets actually connect to route tables? |
| **BACK (Answer)** | • **NO!** In a route table, `cidr_block` specifies the **destination target** where traffic is going, NOT your subnet itself.<br>  - Destination `0.0.0.0/0` ➔ Internet Gateway (`gateway_id`).<br>  - Internal VPC traffic (`10.0.0.0/16` ➔ `local`) is created **automatically** by AWS.<br><br>• **Connecting Subnets:** Subnets are attached to route tables using a separate resource: **`aws_route_table_association`** via their `subnet_id` and `route_table_id`. |

---

## 🎴 Flashcard 12: DRY Resource Naming & Tagging with `locals`

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | How do you avoid repeatedly writing `"${var.project}-${var.env}-<resource>"` across dozens of AWS resources in Terraform? |
| **BACK (Answer)** | Define a reusable `locals` block in `locals.tf`:<br>```hcl\nlocals {\n  name_prefix = "${var.project}-${var.env}"\n  common_tags = {\n    Project     = var.project\n    Environment = var.env\n    ManagedBy   = "terraform"\n  }\n}\n```<br>Then reference it cleanly in resources:<br>```hcl\nName = "${local.name_prefix}-vpc"\nName = "${local.name_prefix}-public-subnet-${count.index + 1}"\n``` |

---

## 🎴 Flashcard 13: AWS NAT Gateway Architecture & Dependencies

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Where must an AWS NAT Gateway be placed, what does it require, and why does private subnet routing depend on it? |
| **BACK (Answer)** | • **Placement:** A NAT Gateway must be placed in a **Public Subnet** (a subnet that has a route to an Internet Gateway).<br>• **Elastic IP:** Requires an Elastic IP (`aws_eip` with `domain = "vpc"`).<br>• **Dependency:** Needs `depends_on = [aws_internet_gateway.main]` so the IGW is active before AWS attempts to allocate the NAT Gateway.<br>• **Private Route Table:** The private route table routes destination `0.0.0.0/0` to `nat_gateway_id = aws_nat_gateway.main.id`, giving private instances outbound internet access without exposing them to inbound internet traffic. |

---

## 🎴 Flashcard 14: VPC DNS Attributes Required for EKS

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | Which two VPC attributes must be explicitly set to `true` when building a VPC for Amazon EKS, and what breaks if they are omitted? |
| **BACK (Answer)** | ```hcl\nresource "aws_vpc" "main" {\n  cidr_block           = var.vpc_cidr\n  enable_dns_hostnames = true\n  enable_dns_support   = true\n}\n```<br>• **Why:** By default in AWS, `enable_dns_hostnames` is `false`.<br>• **What breaks:** Worker node `kubelet` and AWS VPC CNI fail to resolve cluster API server endpoints and cannot register nodes with the EKS control plane. |

---

## 🎴 Flashcard 15: Subnet Tagging for EKS Load Balancer Discovery

| Side | Details |
| :--- | :--- |
| **FRONT (Question)** | What specific AWS tags are required on public and private subnets for the AWS Load Balancer Controller, and what happens if they are missing? |
| **BACK (Answer)** | • **Public Subnets:** `kubernetes.io/role/elb = "1"` (Designates subnets for internet-facing ALBs/NLBs).<br>• **Private Subnets:** `kubernetes.io/role/internal-elb = "1"` (Designates subnets for internal ALBs/NLBs).<br><br>• **Consequence if missing:** The AWS Load Balancer Controller fails to auto-discover subnets and throws error: `failed to resolve subnets: could not find any subnets for load balancer`, unless subnets are hardcoded manually via Kubernetes annotations on every Ingress/Service. |


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

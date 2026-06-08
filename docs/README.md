# Project Diagrams

## Workflow Diagram

**File:** `diagram-workflow.drawio`

### How to View

1. **In Browser (VS Code):** Install the "Draw.io Integration" VS Code extension, then open the file.
2. **Online:** Go to [app.diagrams.net](https://app.diagrams.net) → "Open Existing Diagram" → upload the `.drawio` file.
3. **Export as PNG/SVG:** Open in diagrams.net → File → Export → choose PNG or SVG.

### What the Diagram Shows

The diagram is split into three columns:

| Column | Contents |
|--------|----------|
| **GitHub Repository** (dark bg) | The source repo that triggers everything |
| **Amazon Web Services** (orange bg) | All AWS resources: OIDC Provider, IAM Role, S3 Bucket, EC2 Key Pair, Windows EC2 Instance |
| **GitHub Actions CI/CD** (blue bg) | Three workflows stacked vertically: Terraform Apply → Ansible Provision → Terraform Destroy |

### Color-Coded Arrow Legend

| Arrow Color | Meaning |
|---|---|
| 🟠 Orange | JWT token exchange between GitHub and AWS OIDC |
| 🟢 Green | Terraform apply / temporary AWS credentials |
| 🟣 Purple | WinRM connection / Ansible provisioning |
| 🔴 Red | Destroy / teardown operations |

### Key Resource Boxes

- **OIDC Identity Provider** (`token.actions.githubusercontent.com`) — federates GitHub's identity to AWS
- **IAM Role** (`github-actions-oidc-role`) — granted EC2Full, S3Full, IAMFull, DynamoDBFull
- **S3 Bucket** — Terraform state backend with Object Lock, Versioning, SSE-KMS
- **EC2 Key Pair** — RSA key saved locally at `~/.ssh/terraform-ansible-demo-key.pem`
- **Windows Spot EC2** — Windows Server 2022, t3.micro, Default VPC, Security Group with WinRM+RDP
- **UserData** (inside EC2) — PowerShell script that creates `ansible_admin` and configures WinRM HTTP
- **Ansible Provisioning** (inside EC2) — runs `windows_setup.yml`: creates directory and test file
# Terraform + Ansible CI/CD — Windows Spot EC2

> **Stack:** GitHub Actions · AWS OIDC · Terraform (S3 backend) · Windows Spot EC2 · Ansible WinRM · Dynamic Inventory

---

## Architecture Overview

```
GitHub Push / PR
      │
      ▼
.github/workflows/deploy.yml
      │
      ├─── JOB 1: Terraform Plan  ──► PR comment with plan output
      │
      ├─── JOB 2: Terraform Apply ──► Windows Spot EC2 + SG + IAM
      │                                 (latest Windows 2022 AMI)
      │
      ├─── JOB 3: Ansible         ──► Dynamic Inventory (boto3)
      │                                 ──► WinRM connect
      │                                 ──► Create C:\TestDirectory
      │                                 ──► Create test.txt
      │
      └─── JOB 4: Destroy         ──► Manual trigger only
```

---

## Folder Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml          ← Main CI/CD pipeline (4 jobs)
│
├── ansible/
│   ├── ansible.cfg             ← Ansible configuration
│   ├── inventories/
│   │   ├── aws_ec2_inventory.py  ← Dynamic inventory (boto3)
│   │   └── inventory.ini       ← Static fallback
│   └── playbooks/
│       └── windows_setup.yml   ← Creates directory + test.txt
│
├── scripts/
│   ├── 01_setup_aws_oidc.sh    ← One-time: Create OIDC IAM Role
│   ├── 02_setup_s3_backend.sh  ← One-time: S3 + DynamoDB for state
│   ├── 03_create_ec2_keypair.sh← One-time: EC2 Key Pair
│   └── 04_wait_for_winrm.sh    ← Used by CI: waits for WinRM
│
└── terraform/
    ├── main.tf                 ← Spot EC2, SG, IAM, AMI lookup
    ├── variables.tf            ← All input variables
    ├── outputs.tf              ← Public IP, Instance ID, AMI used
    └── userdata.ps1            ← Bootstraps WinRM on first boot
```

---

## Step-by-Step Setup Guide

### STEP 1 — Prerequisites (run once, locally)

```bash
# Ensure these are installed
aws --version       # AWS CLI v2
terraform --version # >= 1.5
git --version
```

---

### STEP 2 — Run the 3 bootstrap scripts (run once)

```bash
# Make all scripts executable
chmod +x scripts/*.sh

# 2a. Create OIDC IAM Role (edit GITHUB_ORG / GITHUB_REPO inside the script first)
./scripts/01_setup_aws_oidc.sh

# 2b. Create S3 bucket + DynamoDB for Terraform state
./scripts/02_setup_s3_backend.sh

# 2c. Create EC2 Key Pair
./scripts/03_create_ec2_keypair.sh
```

Each script prints the **values you need for GitHub Secrets** at the end.

---

### STEP 3 — Add GitHub Secrets

Go to: `Your Repo → Settings → Secrets and variables → Actions → New repository secret`

| Secret Name | Where to get it |
|---|---|
| `AWS_ROLE_ARN` | Output of `01_setup_aws_oidc.sh` |
| `TF_VAR_tf_state_bucket` | Output of `02_setup_s3_backend.sh` |
| `TF_VAR_tf_lock_table` | `terraform-lock` (default) |
| `TF_VAR_key_name` | Output of `03_create_ec2_keypair.sh` |
| `TF_VAR_ansible_windows_password` | Choose a strong password (e.g. `MySecureP@ss2024!`) |

> **Password requirements:** At least 12 chars, uppercase, lowercase, number, special char.

---

### STEP 4 — Create a GitHub Environment

Go to: `Settings → Environments → New environment → name it: dev`

This is required for `environment: dev` in the workflow.

---

### STEP 5 — Push to GitHub

```bash
git init
git remote add origin https://github.com/YOUR_ORG/terraform-ansible-cicd.git
git add .
git commit -m "feat: initial terraform-ansible-cicd setup"

# Create a PR first to see the plan comment
git checkout -b feature/initial-setup
git push origin feature/initial-setup
# Open PR → GitHub shows Terraform Plan as a comment

# Merge PR → triggers Apply + Ansible
```

---

### STEP 6 — Watch the Pipeline

In GitHub: `Actions tab → "Terraform + Ansible Deploy"`

Jobs run in order:
1. **Terraform Plan** — on PR, posts plan diff as comment
2. **Terraform Apply** — on merge to main, creates the spot instance
3. **Ansible Provision** — waits for WinRM, runs playbook, creates directory + file
4. **Destroy** — only runs if you manually trigger with `action: destroy`

---

### STEP 7 — Verify Results

After Ansible completes, RDP into the instance and verify:

```powershell
# Should exist
ls C:\TestDirectory
Get-Content C:\TestDirectory\test.txt
```

Expected output:
```
Hello from Ansible!
----------------------------------------
Instance  : 13.210.xx.xx
Host Name : EC2AMAZ-XXXXXXX
Date/Time : 2024-xx-xxTxx:xx:xxZ
Managed By: Ansible + GitHub Actions CI/CD
Project   : terraform-ansible-demo
----------------------------------------
```

---

## Manual Destroy

Go to: `Actions → "Terraform + Ansible Deploy" → Run workflow → select "destroy"`

This safely tears down all resources.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `OIDC token error` | Check `AWS_ROLE_ARN` secret and trust policy subject matches your repo |
| `WinRM timeout` | Windows takes 4–8 min to boot. The wait script retries for 10 min |
| `No hosts in inventory` | Check `PROJECT_TAG` env var matches the `Project` tag in Terraform |
| `Spot instance not fulfilled` | Try a different `instance_type` or AZ |
| `Authentication failure` | Confirm `TF_VAR_ansible_windows_password` secret matches userdata password |
| `Backend init error` | Confirm S3 bucket exists and IAM role has S3 access |

---

## Key Design Decisions

- **Spot instance** — `aws_spot_instance_request` with `wait_for_fulfillment = true`
- **Latest AMI** — `data.aws_ami` with `most_recent = true` and Windows 2022 filters
- **Dynamic inventory** — Python script uses boto3 to find running instances by `Project` tag
- **WinRM over HTTP** — Simpler for demo; switch to HTTPS + cert for production
- **OIDC auth** — No long-lived AWS keys stored in GitHub

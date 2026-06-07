#!/bin/bash
# scripts/04_destroy_resources.sh
# --------------------------------
# Destroys all resources created by:
#   01_setup_aws_oidc.sh
#   02_setup_s3_backend.sh
#   03_create_ec2_keypair.sh
#
# Usage:
#   chmod +x scripts/04_destroy_resources.sh
#   ./scripts/04_destroy_resources.sh

set -euo pipefail

# ---- CONFIGURATION ---- Must match the original scripts ----
GITHUB_ORG="mrbalraj007"
GITHUB_REPO="aws-oidc-win-terraform-ansible-cicd"
AWS_REGION="us-east-1"
ROLE_NAME="github-actions-oidc-role"
OIDC_URL="https://token.actions.githubusercontent.com"
KEY_NAME="terraform-ansible-demo-key"
KEY_DIR="$HOME/.ssh"
TODAY=$(date +%Y%m%d)
BUCKET_NAME="${GITHUB_REPO}-${TODAY}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "==> Account    : $ACCOUNT_ID"
echo "==> Region     : $AWS_REGION"
echo "==> GitHub     : $GITHUB_ORG/$GITHUB_REPO"

# ---- Helper ----
confirm() {
  local prompt="$1"
  local response
  read -rp "$prompt [y/N]: " response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# ==============================================================================
# 1. IAM Role — detach policies, delete role
# ==============================================================================
echo ""
echo "==> Checking for IAM Role: $ROLE_NAME"
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" \
  --query "Role.RoleName" --output text 2>/dev/null || echo "None")

if [ "$ROLE_EXISTS" != "None" ]; then
  echo "   Found IAM Role: $ROLE_EXISTS"

  # Detach all managed policies
  echo "   Detaching managed policies..."
  for POLICY_ARN in \
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess" \
    "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" \
    "arn:aws:iam::aws:policy/IAMFullAccess"; do
    aws iam detach-role-policy --role-name "$ROLE_NAME" \
      --policy-arn "$POLICY_ARN" 2>/dev/null \
      && echo "   Detached: $POLICY_ARN" \
      || echo "   (Already detached or not found: $POLICY_ARN)"
  done

  # Delete inline policies (if any)
  echo "   Checking for inline policies..."
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" \
    --query "PolicyNames[*]" --output text 2>/dev/null || echo "")
  if [ -n "$INLINE_POLICIES" ]; then
    for POLICY in $INLINE_POLICIES; do
      aws iam delete-role-policy --role-name "$ROLE_NAME" \
        --policy-name "$POLICY" 2>/dev/null \
        && echo "   Deleted inline policy: $POLICY" \
        || echo "   (Failed to delete inline policy: $POLICY)"
    done
  fi

  # Delete the role
  echo "   Deleting IAM Role..."
  aws iam delete-role --role-name "$ROLE_NAME"
  echo "   IAM Role deleted: $ROLE_NAME"
else
  echo "   IAM Role not found — skipping."
fi

# ==============================================================================
# 2. IAM OIDC Provider
# ==============================================================================
echo ""
echo "==> Checking for OIDC Provider: $OIDC_URL"
OIDC_EXISTS=$(aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" \
  --query "OIDCProviderList" --output text 2>/dev/null || echo "None")

if [ "$OIDC_EXISTS" != "None" ] && [ -n "$OIDC_EXISTS" ]; then
  echo "   Deleting OIDC Provider..."
  aws iam delete-open-id-connect-provider \
    --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
  echo "   OIDC Provider deleted."
else
  echo "   OIDC Provider not found — skipping."
fi

# ==============================================================================
# 3. S3 Bucket — empty and delete
# ==============================================================================
echo ""
echo "==> Checking for S3 Bucket: $BUCKET_NAME"
BUCKET_EXISTS=$(aws s3api head-bucket \
  --bucket "$BUCKET_NAME" 2>&1 || true)

if [ -z "$BUCKET_EXISTS" ] || echo "$BUCKET_EXISTS" | grep -qv "Not Found"; then
  echo "   Found S3 Bucket: $BUCKET_NAME"

  # Object Lock must be disabled before objects can be deleted
  echo "   Disabling Object Lock..."
  aws s3api put-object-lock-configuration \
    --bucket "$BUCKET_NAME" \
    --object-lock-configuration '{"ObjectLockEnabled": "Disabled"}' 2>/dev/null \
    || echo "   (Object Lock may already be disabled or not supported)"

  # Empty the bucket (all versions and delete markers)
  echo "   Emptying bucket (all object versions)..."
  aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query "Objects[*].{Key:Key,VersionId:VersionId}" \
    --output json 2>/dev/null | \
    jq -r '.[] | "--object Key=\(.Key)" + (if .VersionId then " --version-id \(.VersionId)" else "" end)' 2>/dev/null | \
    while read -r line; do
      eval "aws s3api delete-object --bucket \"$BUCKET_NAME\" $line" 2>/dev/null || true
    done

  # Delete delete markers
  aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query "DeleteMarkers[*].{Key:Key,VersionId:VersionId}" \
    --output json 2>/dev/null | \
    jq -r '.[] | "--object Key=\(.Key)" + (if .VersionId then " --version-id \(.VersionId)" else "" end)' 2>/dev/null | \
    while read -r line; do
      eval "aws s3api delete-object --bucket \"$BUCKET_NAME\" $line" 2>/dev/null || true
    done

  # Delete the bucket
  echo "   Deleting S3 Bucket..."
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  echo "   S3 Bucket deleted: $BUCKET_NAME"
else
  echo "   S3 Bucket not found — skipping."
fi

# ==============================================================================
# 4. EC2 Key Pair
# ==============================================================================
echo ""
echo "==> Checking for EC2 Key Pair: $KEY_NAME"
KEY_EXISTS=$(aws ec2 describe-key-pairs \
  --key-names "$KEY_NAME" \
  --region "$AWS_REGION" \
  --query "KeyPairs[0].KeyName" \
  --output text 2>/dev/null || echo "None")

if [ "$KEY_EXISTS" != "None" ] && [ -n "$KEY_EXISTS" ]; then
  echo "   Deleting EC2 Key Pair..."
  aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION"
  echo "   EC2 Key Pair deleted: $KEY_NAME"
else
  echo "   EC2 Key Pair not found — skipping."
fi

# ==============================================================================
# 5. Local private key file
# ==============================================================================
echo ""
echo "==> Checking for local private key: $KEY_DIR/${KEY_NAME}.pem"
if [ -f "$KEY_DIR/${KEY_NAME}.pem" ]; then
  if confirm "   Remove local private key file?"; then
    rm -f "$KEY_DIR/${KEY_NAME}.pem"
    echo "   Private key file removed."
  else
    echo "   Skipped — file保留在你的文件系统中."
  fi
else
  echo "   Local private key file not found — skipping."
fi

# ==============================================================================
# 6. Remove GitHub Secrets
# ==============================================================================
echo ""
echo "==> Cleaning up GitHub Secrets..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  for SECRET in AWS_ROLE_ARN TF_VAR_tf_state_bucket TF_VAR_key_name TF_VAR_ansible_windows_password; do
    if gh secret list --repo "$GITHUB_ORG/$GITHUB_REPO" 2>/dev/null | grep -q "^${SECRET} "; then
      echo "   Deleting GitHub Secret: $SECRET"
      gh secret delete "$SECRET" --repo "$GITHUB_ORG/$GITHUB_REPO" 2>/dev/null \
        && echo "   Deleted: $SECRET" \
        || echo "   (Failed to delete: $SECRET — may need manual removal)"
    else
      echo "   GitHub Secret not found: $SECRET — skipping."
    fi
  done
else
  echo "   ! GitHub CLI not authenticated or not found. Skipping GitHub Secrets cleanup."
  echo "   Manually remove these secrets from GitHub repo settings if needed:"
  echo "      - AWS_ROLE_ARN"
  echo "      - TF_VAR_tf_state_bucket"
  echo "      - TF_VAR_key_name"
  echo "      - TF_VAR_ansible_windows_password"
fi

echo ""
echo "=============================================="
echo "Resource destruction complete!"
echo "  Deleted: IAM Role          ($ROLE_NAME)"
echo "  Deleted: OIDC Provider     (token.actions.githubusercontent.com)"
echo "  Deleted: S3 Bucket         ($BUCKET_NAME)"
echo "  Deleted: EC2 Key Pair      ($KEY_NAME)"
echo "  Cleaned: GitHub Secrets    (AWS_ROLE_ARN, TF_VAR_tf_state_bucket, TF_VAR_key_name, TF_VAR_ansible_windows_password)"
echo "=============================================="
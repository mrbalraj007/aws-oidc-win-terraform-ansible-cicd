#!/bin/bash
# scripts/03_create_ec2_keypair.sh
# ---------------------------------
# Creates an EC2 Key Pair and saves the private key locally.
# The key name is then added as a GitHub Actions secret.
#
# Usage:
#   chmod +x scripts/03_create_ec2_keypair.sh
#   ./scripts/03_create_ec2_keypair.sh

set -euo pipefail

# ---- CONFIGURATION ---- Edit these ----
AWS_REGION="us-east-1"
KEY_NAME="terraform-ansible-demo-key"
KEY_DIR="$HOME/.ssh"

echo "==> Creating EC2 Key Pair: $KEY_NAME"
echo "==> Region: $AWS_REGION"

mkdir -p "$KEY_DIR"
KEY_FILE="$KEY_DIR/${KEY_NAME}.pem"

# Check if key already exists in AWS
EXISTING=$(aws ec2 describe-key-pairs \
  --key-names "$KEY_NAME" \
  --region "$AWS_REGION" \
  --query "KeyPairs[0].KeyName" \
  --output text 2>/dev/null || echo "None")

if [ "$EXISTING" != "None" ] && [ "$EXISTING" != "" ]; then
  echo "   Key pair '$KEY_NAME' already exists in AWS."
  echo "   If you need the private key, delete and recreate it."
else
  # Create and save
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query "KeyMaterial" \
    --output text \
    --region "$AWS_REGION" > "$KEY_FILE"

  chmod 600 "$KEY_FILE"
  echo "   Private key saved to: $KEY_FILE"
fi

# Try to add the secret to GitHub Actions using gh CLI
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        echo "==> Adding TF_VAR_key_name secret to GitHub Actions repository..."
        if gh secret set TF_VAR_key_name --body "$KEY_NAME" >/dev/null 2>&1; then
            echo "   Secret TF_VAR_key_name set successfully."
        else
            echo "   ! Failed to set secret TF_VAR_key_name. You may need to set it manually."
        fi
    else
        echo "   ! GitHub CLI is not authenticated. Please run 'gh auth login' and then rerun this script to automatically set the secret."
        echo "   ! Alternatively, you can set the secret manually as shown below."
    fi
else
    echo "   ! GitHub CLI (gh) not found. Please install it to automatically set the secret."
    echo "   ! Alternatively, you can set the secret manually as shown below."
fi

echo ""
echo "=============================================="
echo "Key Pair setup complete!"
echo "Add these secrets to GitHub Actions:"
echo "  TF_VAR_key_name = terraform-ansible-demo-key"
echo ""
echo "If you need to decode the Windows password:"
echo "  aws ec2 get-password-data \\"
echo "    --instance-id <INSTANCE_ID> \\"
echo "    --priv-launch-key $KEY_FILE \\"
echo "    --region $AWS_REGION"
echo "=============================================="
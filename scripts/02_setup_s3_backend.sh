   #!/bin/bash
   # scripts/02_setup_s3_backend.sh
   # --------------------------------
   # Creates an S3 bucket with Object Lock for Terraform remote state.
   # Uses S3 native lockfile (use_lockfile = true) instead of DynamoDB.
   #
   # Usage:
   #   chmod +x scripts/02_setup_s3_backend.sh
   #   ./scripts/02_setup_s3_backend.sh

   set -euo pipefail

   # ---- CONFIGURATION ---- Edit these ----
   AWS_REGION="us-east-1"
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   TODAY=$(date +%Y%m%d)
   GITHUB_REPO=$(gh repo view --json name --jq .name)
   BUCKET_NAME="${GITHUB_REPO}-${TODAY}"
   GITHUB_ORG="mrbalraj007"

   echo "==> Account    : $ACCOUNT_ID"
   echo "==> Bucket     : $BUCKET_NAME"
   echo "==> Region     : $AWS_REGION"

   # ---- Create S3 Bucket with Object Lock ----
   echo ""
   echo "==> Creating S3 bucket with Object Lock..."
   if [ "$AWS_REGION" = "us-east-1" ]; then
     aws s3api create-bucket \
       --bucket "$BUCKET_NAME" \
       --region "$AWS_REGION" || true
   else
     aws s3api create-bucket \
       --bucket "$BUCKET_NAME" \
       --region "$AWS_REGION" \
       --create-bucket-configuration LocationConstraint="$AWS_REGION" || true
   fi

   # Enable versioning (required for Object Lock)
   aws s3api put-bucket-versioning \
     --bucket "$BUCKET_NAME" \
     --versioning-configuration Status=Enabled

   # Enable Object Lock (WORM protection)
   aws s3api put-object-lock-configuration \
     --bucket "$BUCKET_NAME" \
     --object-lock-configuration '{"ObjectLockEnabled": "Enabled", "Rule": {"DefaultRetention": {"Mode": "GOVERNANCE", "Days": 7}}}'

   # Enable encryption
   aws s3api put-bucket-encryption \
     --bucket "$BUCKET_NAME" \
     --server-side-encryption-configuration '{
       "Rules": [{
         "ApplyServerSideEncryptionByDefault": {
           "SSEAlgorithm": "AES256"
         }
       }]
     }'

   # Block public access
   aws s3api put-public-access-block \
     --bucket "$BUCKET_NAME" \
     --public-access-block-configuration \
       "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

   echo "   S3 bucket ready: $BUCKET_NAME (Object Lock enabled)"

   # ---- Add TF_VAR_tf_state_bucket secret to GitHub Actions ----
   echo ""
   echo "==> Adding TF_VAR_tf_state_bucket secret to GitHub Actions..."
   gh secret set TF_VAR_tf_state_bucket --body "$BUCKET_NAME" \
     --repo "$GITHUB_ORG/$GITHUB_REPO"

   echo ""
   echo "=============================================="
   echo "S3 backend setup complete!"
   echo "  Secret: TF_VAR_tf_state_bucket = $BUCKET_NAME"
   echo "  Note   : Uses S3 native lockfile (no DynamoDB)"

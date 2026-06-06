#!/bin/bash

################################################################################
# Deploy IAM Roles CloudFormation Stack
# Purpose: Create IAM roles in each AWS account
# Usage: bash deploy-iam-roles.sh <ACCOUNT_PROFILE> <MANAGEMENT_ACCOUNT_ID>
################################################################################

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <ACCOUNT_PROFILE> <MANAGEMENT_ACCOUNT_ID>"
    echo "Example: $0 development 123456789012"
    exit 1
fi

PROFILE=$1
MANAGEMENT_ACCOUNT=$2
REGION="us-east-1"
STACK_NAME="iam-roles-stack"

echo "[INFO] Deploying IAM roles to account profile: $PROFILE"
echo "[INFO] Management Account ID: $MANAGEMENT_ACCOUNT"

# Verify profile exists
if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "[ERROR] AWS profile '$PROFILE' not found or not configured"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "[INFO] Target Account ID: $ACCOUNT_ID"

# Deploy CloudFormation stack
echo "[INFO] Deploying CloudFormation stack: $STACK_NAME"
aws cloudformation deploy \
    --template-file iam-roles.yaml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides ManagementAccountId="$MANAGEMENT_ACCOUNT" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --capabilities CAPABILITY_NAMED_IAM

if [ $? -eq 0 ]; then
    echo "[SUCCESS] IAM roles deployed successfully to account $ACCOUNT_ID"
    
    # Output role ARNs
    echo ""
    echo "[INFO] IAM Role ARNs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'Stacks[0].Outputs' \
        --output table
else
    echo "[ERROR] Failed to deploy IAM roles"
    exit 1
fi

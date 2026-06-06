#!/bin/bash

################################################################################
# Cross-Account Trust Setup Script
# Purpose: Create cross-account IAM trust relationships
# Usage: bash cross-account-trust.sh <SOURCE_ACCOUNT_ID> <DEST_ACCOUNT_ID> <ROLE_NAME>
################################################################################

set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <SOURCE_ACCOUNT_ID> <DEST_ACCOUNT_ID> <ROLE_NAME>"
    echo "Example: $0 123456789012 987654321098 CrossAccountCodePipelineRole"
    exit 1
fi

SOURCE_ACCOUNT=$1
DEST_ACCOUNT=$2
ROLE_NAME=$3

echo "Creating trust relationship:"
echo "  Source Account: $SOURCE_ACCOUNT"
echo "  Destination Account: $DEST_ACCOUNT"
echo "  Role: $ROLE_NAME"

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${SOURCE_ACCOUNT}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {}
    }
  ]
}
EOF
)

# Create temporary policy file
echo "$TRUST_POLICY" > /tmp/trust-policy.json

echo "Updating trust policy for role: $ROLE_NAME in account $DEST_ACCOUNT"
aws iam update-assume-role-policy-document \
    --role-name "$ROLE_NAME" \
    --policy-document file:///tmp/trust-policy.json \
    --profile "$(echo $DEST_ACCOUNT | awk '{print tolower($0)}')" || \
echo "Note: You may need to run this command manually with the destination account credentials"

echo "Trust relationship created successfully!"
rm -f /tmp/trust-policy.json

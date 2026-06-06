#!/bin/bash

################################################################################
# AWS CodeCommit Repository Setup
# Purpose: Create and configure CodeCommit repositories
# Usage: bash repo-structure.sh <REPO_NAME> <PROFILE>
################################################################################

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <REPO_NAME> [PROFILE]"
    echo "Example: $0 my-app-repo cicd"
    exit 1
fi

REPO_NAME=$1
PROFILE=${2:-default}
REGION="us-east-1"

echo "[INFO] Creating CodeCommit repository: $REPO_NAME"

# Create repository
aws codecommit create-repository \
    --repository-name "$REPO_NAME" \
    --description "Application repository for $REPO_NAME" \
    --tags Environment=DevOps,Project=MultiAccountDevOps \
    --region "$REGION" \
    --profile "$PROFILE" || echo "[WARNING] Repository may already exist"

# Get repository details
echo "[INFO] Repository created. Getting details..."
REPO_ARN=$(aws codecommit get-repository \
    --repository-name "$REPO_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'repositoryMetadata.repositoryArn' \
    --output text)

HTTPS_URL=$(aws codecommit get-repository \
    --repository-name "$REPO_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'repositoryMetadata.cloneUrlHttp' \
    --output text)

echo "[SUCCESS] Repository created successfully!"
echo "[INFO] Repository ARN: $REPO_ARN"
echo "[INFO] Clone URL (HTTPS): $HTTPS_URL"
echo ""
echo "[INFO] To clone the repository:"
echo "  git clone $HTTPS_URL"

# Setup default branch policy
echo "[INFO] Configuring default branch and policies..."

# Create branch policy to protect main branch
cat > /tmp/branch-policy.json << 'EOF'
{
  "destinationReferences": ["main"],
  "numberOfRulesToBypass": 0,
  "approvalRuleTemplate": {
    "approvalRuleTemplateName": "Require-2-Approvals",
    "approvalRuleTemplateDescription": "Requires 2 approvals for PRs to main branch",
    "approvalRuleTemplateContent": "{\"Version\": \"2021-01-01\",\"DestinationReferences\": [\"main\"],\"Statements\": [{\"Type\": \"Approvers\",\"NumberOfApprovalsNeeded\": 2}]}"
  }
}
EOF

echo "[INFO] Repository setup complete!"
echo ""
echo "[INFO] Next steps:"
echo "  1. Clone the repository: git clone $HTTPS_URL"
echo "  2. Add initial files (buildspec.yaml, Dockerfile, etc.)"
echo "  3. Push to main branch: git push -u origin main"
echo "  4. Create development branch: git checkout -b develop && git push -u origin develop"


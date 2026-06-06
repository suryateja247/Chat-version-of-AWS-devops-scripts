#!/bin/bash

################################################################################
# AWS CodeBuild Project Setup
# Purpose: Create CodeBuild projects for CI/CD pipeline
# Usage: bash build-setup.sh <PROJECT_NAME> <REPO_NAME> <PROFILE> <AWS_REGION>
################################################################################

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <PROJECT_NAME> <REPO_NAME> [PROFILE] [REGION]"
    echo "Example: $0 my-app-build my-app-repo cicd us-east-1"
    exit 1
fi

PROJECT_NAME=$1
REPO_NAME=$2
PROFILE=${3:-default}
REGION=${4:-us-east-1}

echo "[INFO] Creating CodeBuild project: $PROJECT_NAME"
echo "[INFO] Repository: $REPO_NAME"
echo "[INFO] Region: $REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "[INFO] Account ID: $ACCOUNT_ID"

# Create ECR repository
echo "[INFO] Creating ECR repository..."
aws ecr create-repository \
    --repository-name "${PROJECT_NAME}" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --tags Key=Project,Value="$PROJECT_NAME" || echo "[WARNING] ECR repository may already exist"

# Create S3 bucket for artifacts
ARTIFACT_BUCKET="${PROJECT_NAME}-artifacts-${ACCOUNT_ID}"
echo "[INFO] Creating S3 artifact bucket: $ARTIFACT_BUCKET"
aws s3 mb "s3://${ARTIFACT_BUCKET}" --region "$REGION" --profile "$PROFILE" || echo "[WARNING] Bucket may already exist"

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket "$ARTIFACT_BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$REGION" \
    --profile "$PROFILE"

# Create CodeBuild service role
ROLE_NAME="${PROJECT_NAME}-CodeBuildRole"
echo "[INFO] Creating IAM role: $ROLE_NAME"

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --profile "$PROFILE" || echo "[WARNING] Role may already exist"

# Attach policies to role
echo "[INFO] Attaching policies to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
    --profile "$PROFILE"

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --profile "$PROFILE"

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
    --profile "$PROFILE"

# Create inline policy for CodeCommit access
echo "[INFO] Adding CodeCommit access policy..."
CODECOMMIT_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codecommit:GitPull"
      ],
      "Resource": "arn:aws:codecommit:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}'

aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "${PROJECT_NAME}-CodeCommitAccess" \
    --policy-document "$CODECOMMIT_POLICY" \
    --profile "$PROFILE"

# Wait for role to be available
echo "[INFO] Waiting for IAM role to be available..."
sleep 10

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.Arn' --output text)
echo "[INFO] Role ARN: $ROLE_ARN"

# Create CodeBuild project
echo "[INFO] Creating CodeBuild project..."
aws codebuild create-project \
    --name "$PROJECT_NAME" \
    --source type=CODECOMMIT,location="https://git-codecommit.${REGION}.amazonaws.com/v1/repos/${REPO_NAME}" \
    --source-version main \
    --artifacts type=S3,location="${ARTIFACT_BUCKET}" \
    --cache type=S3,location="${ARTIFACT_BUCKET}/build-cache" \
    --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_SMALL,environmentVariables="[{name=AWS_ACCOUNT_ID,value=${ACCOUNT_ID},type=PLAINTEXT},{name=AWS_DEFAULT_REGION,value=${REGION},type=PLAINTEXT},{name=IMAGE_REPO_NAME,value=${PROJECT_NAME},type=PLAINTEXT},{name=ARTIFACT_BUCKET,value=${ARTIFACT_BUCKET},type=PLAINTEXT}]" \
    --service-role "$ROLE_ARN" \
    --logs-config cloudWatchLogs={status=ENABLED,groupName=/aws/codebuild/${PROJECT_NAME}} \
    --region "$REGION" \
    --profile "$PROFILE" || echo "[WARNING] Project may already exist"

echo "[SUCCESS] CodeBuild project created successfully!"
echo ""
echo "[INFO] Next steps:"
echo "  1. Add buildspec.yaml to your repository root"
echo "  2. Configure the project source to use your branch preference"
echo "  3. Run: aws codebuild batch-get-projects --names $PROJECT_NAME --region $REGION"
echo "  4. Start a build: aws codebuild start-build --project-name $PROJECT_NAME --region $REGION"


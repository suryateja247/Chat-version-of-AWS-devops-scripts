#!/bin/bash

################################################################################
# CodeCommit Webhook Setup for CodePipeline
# Purpose: Configure webhooks to trigger CodePipeline on code push
# Usage: bash webhook-config.sh <REPO_NAME> <PIPELINE_NAME> <PROFILE>
################################################################################

set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <REPO_NAME> <PIPELINE_NAME> <PROFILE>"
    echo "Example: $0 my-app-repo my-app-pipeline cicd"
    exit 1
fi

REPO_NAME=$1
PIPELINE_NAME=$2
PROFILE=$3
REGION="us-east-1"

echo "[INFO] Setting up CodeCommit webhook for $REPO_NAME"
echo "[INFO] Pipeline: $PIPELINE_NAME"

# Get CodePipeline ARN
PIPELINE_ARN=$(aws codepipeline get-pipeline \
    --name "$PIPELINE_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'pipeline.pipelineArn' \
    --output text)

echo "[INFO] Pipeline ARN: $PIPELINE_ARN"

# In AWS, CodeCommit triggers CodePipeline through EventBridge rules
# Create EventBridge rule to trigger pipeline on CodeCommit push

echo "[INFO] Creating EventBridge rule for CodeCommit push events..."

EVENT_RULE_NAME="${REPO_NAME}-to-${PIPELINE_NAME}-rule"

aws events put-rule \
    --name "$EVENT_RULE_NAME" \
    --event-pattern "{
        \"source\": [\"aws.codecommit\"],
        \"detail-type\": [\"CodeCommit Repository State Change\"],
        \"detail\": {
            \"event\": [\"referenceCreated\", \"referenceUpdated\"],
            \"referenceType\": [\"branch\"],
            \"referenceName\": [\"main\", \"develop\"],
            \"repositoryName\": [\"${REPO_NAME}\"]
        }
    }" \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] EventBridge rule created: $EVENT_RULE_NAME"

# Add CodePipeline as target
echo "[INFO] Adding CodePipeline as target to EventBridge rule..."

aws events put-targets \
    --rule "$EVENT_RULE_NAME" \
    --targets "Id=1,Arn=${PIPELINE_ARN},RoleArn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text --profile $PROFILE):role/CodePipelineEventBridgeRole" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[SUCCESS] CodeCommit webhook configured successfully!"
echo "[INFO] Repository: $REPO_NAME will trigger $PIPELINE_NAME on push to main/develop branches"


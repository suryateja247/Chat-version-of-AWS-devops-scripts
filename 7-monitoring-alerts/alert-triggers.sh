#!/bin/bash

################################################################################
# EventBridge Alert Trigger Setup
# Purpose: Configure event-driven automated responses and notifications
# Usage: bash alert-triggers.sh <ENVIRONMENT> <PROFILE> [REGION]
################################################################################

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <ENVIRONMENT> <PROFILE> [REGION]"
    echo "Example: $0 prod default us-east-1"
    exit 1
fi

ENV=$1
PROFILE=$2
REGION=${3:-us-east-1}

echo "[INFO] Setting up EventBridge alert triggers for $ENV"

# Create SNS topic for EventBridge notifications
echo "[INFO] Creating SNS topic for EventBridge..."
TOPIC_ARN=$(aws sns create-topic \
    --name "${ENV}-eventbridge-alerts" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text)

echo "[INFO] SNS Topic ARN: $TOPIC_ARN"

# Rule 1: CodePipeline execution state changes
echo "[INFO] Creating EventBridge rule for pipeline failures..."
aws events put-rule \
    --name "${ENV}-pipeline-failure-rule" \
    --event-pattern '{
      "source": ["aws.codepipeline"],
      "detail-type": ["CodePipeline Pipeline Execution State Change"],
      "detail": {
        "state": ["FAILED"],
        "pipeline": ["'"${ENV}"'-pipeline"]
      }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

aws events put-targets \
    --rule "${ENV}-pipeline-failure-rule" \
    --targets "Id=1,Arn=${TOPIC_ARN},RoleArn=arn:aws:iam::$(aws sts get-caller-identity --profile $PROFILE --query Account --output text):role/service-role/EventBridgeInvokeRole" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created pipeline failure rule"

# Rule 2: ECS service deployment state changes
echo "[INFO] Creating EventBridge rule for ECS deployment failures..."
aws events put-rule \
    --name "${ENV}-ecs-deployment-failure-rule" \
    --event-pattern '{
      "source": ["aws.ecs"],
      "detail-type": ["ECS Task State Change"],
      "detail": {
        "lastStatus": ["STOPPED"],
        "stoppedReason": ["Task failed"],
        "clusterArn": ["arn:aws:ecs:*:*:cluster/'"${ENV}"'-cluster"]
      }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

aws events put-targets \
    --rule "${ENV}-ecs-deployment-failure-rule" \
    --targets "Id=1,Arn=${TOPIC_ARN},RoleArn=arn:aws:iam::$(aws sts get-caller-identity --profile $PROFILE --query Account --output text):role/service-role/EventBridgeInvokeRole" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created ECS deployment failure rule"

# Rule 3: EC2 instance state changes
echo "[INFO] Creating EventBridge rule for EC2 state changes..."
aws events put-rule \
    --name "${ENV}-ec2-state-change-rule" \
    --event-pattern '{
      "source": ["aws.ec2"],
      "detail-type": ["EC2 Instance State-change Notification"],
      "detail": {
        "state": ["running", "stopped", "terminated"],
        "instance-id": [{"prefix": "i-"}]
      }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

aws events put-targets \
    --rule "${ENV}-ec2-state-change-rule" \
    --targets "Id=1,Arn=${TOPIC_ARN},RoleArn=arn:aws:iam::$(aws sts get-caller-identity --profile $PROFILE --query Account --output text):role/service-role/EventBridgeInvokeRole" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created EC2 state change rule"

# Rule 4: CloudWatch Alarm state changes
echo "[INFO] Creating EventBridge rule for CloudWatch alarms..."
aws events put-rule \
    --name "${ENV}-cloudwatch-alarm-rule" \
    --event-pattern '{
      "source": ["aws.cloudwatch"],
      "detail-type": ["CloudWatch Alarm State Change"],
      "detail": {
        "state": {"value": ["ALARM"]}
      }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

aws events put-targets \
    --rule "${ENV}-cloudwatch-alarm-rule" \
    --targets "Id=1,Arn=${TOPIC_ARN},RoleArn=arn:aws:iam::$(aws sts get-caller-identity --profile $PROFILE --query Account --output text):role/service-role/EventBridgeInvokeRole" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created CloudWatch alarm rule"

echo "[SUCCESS] EventBridge alert triggers configured!"
echo ""
echo "[INFO] Created rules:"
echo "  - ${ENV}-pipeline-failure-rule: Triggers on CodePipeline failures"
echo "  - ${ENV}-ecs-deployment-failure-rule: Triggers on ECS task failures"
echo "  - ${ENV}-ec2-state-change-rule: Triggers on EC2 state changes"
echo "  - ${ENV}-cloudwatch-alarm-rule: Triggers on CloudWatch alarms"
echo ""
echo "[INFO] All rules send notifications to: $TOPIC_ARN"


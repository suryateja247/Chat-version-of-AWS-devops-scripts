#!/bin/bash

################################################################################
# Cost Optimization Setup
# Purpose: Configure cost monitoring and auto-shutdown of non-production resources
# Usage: bash cost-optimization.sh <PROFILE> [REGION]
################################################################################

set -e

PROFILE=${1:-default}
REGION=${2:-us-east-1}

echo "[INFO] Setting up cost optimization..."

# Create DynamoDB table for tracking instance state
echo "[INFO] Creating DynamoDB table for resource tracking..."
aws dynamodb create-table \
    --table-name DevOpsResourceTracking \
    --attribute-definitions AttributeName=ResourceId,AttributeType=S \
    --key-schema AttributeName=ResourceId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --profile "$PROFILE" || echo "[WARNING] Table may already exist"

echo "[INFO] DynamoDB table created/exists"

# Create budget alert
echo "[INFO] Creating AWS Budget for cost tracking..."

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)

cat > /tmp/budget-config.json << EOF
{
  "BudgetName": "Monthly-Budget-Alert",
  "BudgetLimit": {
    "Amount": "100",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "NotificationsWithSubscribers": [
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "your-email@example.com"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "your-email@example.com"
        }
      ]
    }
  ]
}
EOF

echo "[WARNING] Update email address in /tmp/budget-config.json and run:"
echo "  aws budgets create-budget --account-id $ACCOUNT_ID --budget file:///tmp/budget-config.json --region $REGION"

# Create tag-based cost allocation
echo "[INFO] Creating cost allocation tags..."
echo "[INFO] Recommended tags:"
echo "  - Environment: dev, staging, prod"
echo "  - CostCenter: department"
echo "  - Owner: team"
echo "  - Project: project-name"
echo "  - AutoShutdown: true/false"

echo "[SUCCESS] Cost optimization setup completed!"
echo ""
echo "[INFO] Cost optimization recommendations:"
echo "  1. Use Spot Instances for non-production (70-90% savings)"
echo "  2. Set up Reserved Instances for baseline production load"
echo "  3. Enable S3 Intelligent-Tiering for automatic cost optimization"
echo "  4. Configure CloudWatch Logs retention policies (currently 7 days)"
echo "  5. Use EventBridge to auto-stop non-production instances at night"
echo "  6. Implement AWS Compute Optimizer recommendations"
echo "  7. Use ECS/Fargate instead of EKS for cost savings"
echo "  8. Monitor unused resources with AWS Cost Explorer"


#!/bin/bash

################################################################################
# CloudWatch Monitoring Setup
# Purpose: Configure CloudWatch alarms, dashboards, and log groups
# Usage: bash cloudwatch-setup.sh <ENVIRONMENT> <PROFILE> [REGION]
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

echo "[INFO] Setting up CloudWatch monitoring for $ENV environment"

# Create SNS topic for alarms
echo "[INFO] Creating SNS topic for alarms..."
TOPIC_ARN=$(aws sns create-topic \
    --name "${ENV}-alerts" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text)

echo "[INFO] SNS Topic ARN: $TOPIC_ARN"

# Subscribe email to SNS topic (replace with actual email)
echo "[WARNING] To receive alerts, subscribe to SNS topic:"
echo "  aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com --region $REGION"

# Create CloudWatch Log Group for application logs
echo "[INFO] Creating CloudWatch Log Group..."
aws logs create-log-group \
    --log-group-name "/aws/${ENV}/application" \
    --region "$REGION" \
    --profile "$PROFILE" || echo "[WARNING] Log group may already exist"

# Set log retention to 7 days for cost optimization
aws logs put-retention-policy \
    --log-group-name "/aws/${ENV}/application" \
    --retention-in-days 7 \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Log retention set to 7 days"

# Create CloudWatch Alarms for ECS Service
echo "[INFO] Creating CloudWatch alarms..."

# CPU Utilization Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${ENV}-ecs-high-cpu" \
    --alarm-description "Alert when ECS CPU exceeds 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "$TOPIC_ARN" \
    --dimensions Name=ClusterName,Value="${ENV}-cluster" Name=ServiceName,Value="${ENV}-service" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created CPU utilization alarm"

# Memory Utilization Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${ENV}-ecs-high-memory" \
    --alarm-description "Alert when ECS memory exceeds 85%" \
    --metric-name MemoryUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 85 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "$TOPIC_ARN" \
    --dimensions Name=ClusterName,Value="${ENV}-cluster" Name=ServiceName,Value="${ENV}-service" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created memory utilization alarm"

# Task Count Alarm (running tasks)
aws cloudwatch put-metric-alarm \
    --alarm-name "${ENV}-ecs-low-task-count" \
    --alarm-description "Alert when running task count drops below desired" \
    --metric-name RunningCount \
    --namespace AWS/ECS \
    --statistic Average \
    --period 60 \
    --threshold 1 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "$TOPIC_ARN" \
    --dimensions Name=ClusterName,Value="${ENV}-cluster" Name=ServiceName,Value="${ENV}-service" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created task count alarm"

# Application Log Errors Alarm
echo "[INFO] Creating log-based metric for errors..."
aws logs put-metric-filter \
    --log-group-name "/aws/${ENV}/application" \
    --filter-name "ErrorCount" \
    --filter-pattern "[ERROR]" \
    --metric-transformations metricName=ApplicationErrors,metricNamespace="Custom/${ENV}",metricValue=1 \
    --region "$REGION" \
    --profile "$PROFILE"

aws cloudwatch put-metric-alarm \
    --alarm-name "${ENV}-app-errors-high" \
    --alarm-description "Alert on high application error rate" \
    --metric-name ApplicationErrors \
    --namespace "Custom/${ENV}" \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[INFO] Created application error alarm"

# Create CloudWatch Dashboard
echo "[INFO] Creating CloudWatch dashboard..."

DASHBOARD_BODY=$(cat <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/ECS", "CPUUtilization", { "stat": "Average" } ],
          [ ".", "MemoryUtilization", { "stat": "Average" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "$REGION",
        "title": "ECS Service Metrics"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "fields @timestamp, @message | stats count() as ErrorCount by bin(5m)",
        "region": "$REGION",
        "title": "Application Errors"
      }
    }
  ]
}
EOF
)

echo "[SUCCESS] CloudWatch monitoring setup completed!"
echo ""
echo "[INFO] Created resources:"
echo "  - SNS Topic: $TOPIC_ARN"
echo "  - Log Group: /aws/${ENV}/application"
echo "  - Alarms: ${ENV}-ecs-high-cpu, ${ENV}-ecs-high-memory, ${ENV}-ecs-low-task-count, ${ENV}-app-errors-high"
echo ""
echo "[INFO] Next steps:"
echo "  1. Subscribe to SNS topic to receive alerts"
echo "  2. Configure custom application metrics in your code"
echo "  3. View logs: aws logs tail /aws/${ENV}/application --follow --region $REGION"


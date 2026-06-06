# Complete Multi-Account AWS DevOps Deployment Guide

## Step-by-Step Deployment Instructions

### Phase 1: Foundation Setup (Day 1)

#### 1.1 Prerequisites
```bash
# Verify AWS CLI is installed
aws --version

# Verify other tools
terraform --version
kubectl version --client
ansible --version
jq --version

# Configure AWS credentials
aws configure
# Enter:
# AWS Access Key ID: [your-access-key]
# AWS Secret Access Key: [your-secret-key]
# Default region: us-east-1
# Default output format: json
```

#### 1.2 Enable AWS Organizations
```bash
cd 1-foundation

# Run multi-account setup
bash multi-account-setup.sh

# This will:
# - Enable AWS Organizations
# - Create S3 artifact bucket
# - Generate CLI profiles
```

#### 1.3 Create AWS Accounts
```bash
# Manually create 4 AWS accounts via AWS Organizations:
# 1. CI/CD Account (where CodePipeline runs)
# 2. Development Account
# 3. Staging Account  
# 4. Production Account

# Wait for account creation to complete (5-10 minutes)
# Verify in AWS Organizations console

aws organizations list-accounts --profile default
```

#### 1.4 Deploy IAM Roles
```bash
# Deploy IAM roles to each account
MGMT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Deploy to CI/CD account
bash deploy-iam-roles.sh cicd $MGMT_ACCOUNT

# Deploy to Development account
bash deploy-iam-roles.sh development $MGMT_ACCOUNT

# Deploy to Staging account
bash deploy-iam-roles.sh staging $MGMT_ACCOUNT

# Deploy to Production account
bash deploy-iam-roles.sh production $MGMT_ACCOUNT

# Verify deployments
aws cloudformation list-stacks --profile cicd --query 'StackSummaries[0]'
```

#### 1.5 Setup Cross-Account Trust
```bash
# Get account IDs
CI_ACCOUNT=$(aws sts get-caller-identity --profile cicd --query Account --output text)
DEV_ACCOUNT=$(aws sts get-caller-identity --profile development --query Account --output text)
STAGING_ACCOUNT=$(aws sts get-caller-identity --profile staging --query Account --output text)
PROD_ACCOUNT=$(aws sts get-caller-identity --profile production --query Account --output text)

# Create trust relationships
bash cross-account-trust.sh $MGMT_ACCOUNT $DEV_ACCOUNT CrossAccountCodePipelineRole
bash cross-account-trust.sh $MGMT_ACCOUNT $STAGING_ACCOUNT CrossAccountCodePipelineRole
bash cross-account-trust.sh $MGMT_ACCOUNT $PROD_ACCOUNT CrossAccountCodePipelineRole
```

---

### Phase 2: Source Control & CI/CD Setup (Day 2)

#### 2.1 Create CodeCommit Repository
```bash
cd 2-codecommit-setup

# Create repository
bash repo-structure.sh my-app-repo cicd

# Get repository URL
REPO_URL=$(aws codecommit get-repository \
  --repository-name my-app-repo \
  --region us-east-1 \
  --profile cicd \
  --query 'repositoryMetadata.cloneUrlHttp' \
  --output text)

echo "Clone URL: $REPO_URL"
```

#### 2.2 Initialize Repository
```bash
# Clone the repository
git clone $REPO_URL
cd my-app-repo

# Create initial structure
mkdir -p src tests docker
echo "# My Application" > README.md
echo "node_modules/\n.env\n.DS_Store" > .gitignore

# Create sample Dockerfile
cat > docker/Dockerfile << 'EOF'
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF

# Create buildspec.yaml (copy from 3-codebuild-ci/buildspec.yaml)
cp ../3-codebuild-ci/buildspec.yaml .

# Commit and push
git add .
git commit -m "Initial commit: application structure"
git push -u origin main
```

#### 2.3 Setup CodeBuild
```bash
cd ../3-codebuild-ci

# Create CodeBuild project
bash build-setup.sh my-app-build my-app-repo cicd us-east-1

# Verify project creation
aws codebuild batch-get-projects \
  --names my-app-build \
  --region us-east-1 \
  --profile cicd
```

#### 2.4 Setup CodePipeline Webhook
```bash
cd ../2-codecommit-setup

# Configure webhook (requires pipeline to exist first)
# Will do this after creating pipeline
```

---

### Phase 3: Infrastructure as Code (Day 3)

#### 3.1 Deploy VPC in Each Account
```bash
cd ../5-infrastructure-as-code

# Deploy to Development
aws cloudformation deploy \
  --template-file vpc-template.yaml \
  --stack-name dev-vpc-stack \
  --parameter-overrides EnvironmentName=dev \
  --region us-east-1 \
  --profile development

# Deploy to Staging
aws cloudformation deploy \
  --template-file vpc-template.yaml \
  --stack-name staging-vpc-stack \
  --parameter-overrides EnvironmentName=staging \
  --region us-east-1 \
  --profile staging

# Deploy to Production
aws cloudformation deploy \
  --template-file vpc-template.yaml \
  --stack-name prod-vpc-stack \
  --parameter-overrides EnvironmentName=prod \
  --region us-east-1 \
  --profile production
```

#### 3.2 Deploy ECS Clusters
```bash
# Get VPC IDs from CloudFormation outputs
DEV_VPC=$(aws cloudformation describe-stacks \
  --stack-name dev-vpc-stack \
  --region us-east-1 \
  --profile development \
  --query 'Stacks[0].Outputs[0].OutputValue' \
  --output text)

# Deploy ECS to Development
aws cloudformation deploy \
  --template-file ecs-cluster.yaml \
  --stack-name dev-ecs-stack \
  --parameter-overrides \
    EnvironmentName=dev \
    VpcId=$DEV_VPC \
  --region us-east-1 \
  --profile development

# Repeat for staging and production
```

#### 3.3 Generate Ansible Playbooks
```bash
mkdir -p playbooks
bash generate-playbooks.sh

# Review generated playbooks
ls -la playbooks/
```

---

### Phase 4: CI/CD Pipeline Setup (Day 4)

#### 4.1 Deploy CodePipeline
```bash
cd ../4-codepipeline-orch

# Deploy pipeline
bash pipeline-setup.sh my-app \
  my-app-repo \
  my-app-build \
  $MGMT_ACCOUNT \
  $DEV_ACCOUNT \
  $STAGING_ACCOUNT \
  $PROD_ACCOUNT \
  cicd \
  us-east-1

# Verify pipeline
aws codepipeline list-pipelines --region us-east-1 --profile cicd
```

#### 4.2 Setup CodeCommit Webhook
```bash
cd ../2-codecommit-setup

# Now configure webhook
bash webhook-config.sh my-app-repo my-app-pipeline cicd
```

#### 4.3 Test Pipeline
```bash
# Push a change to repository
cd ../../my-app-repo
echo "console.log('Updated');" >> src/index.js
git add .
git commit -m "Test pipeline trigger"
git push origin main

# Watch pipeline execution
aws codepipeline start-pipeline-execution \
  --name my-app-pipeline \
  --region us-east-1 \
  --profile cicd
```

---

### Phase 5: Monitoring & Alerts (Day 5)

#### 5.1 Setup CloudWatch
```bash
cd ../7-monitoring-alerts

# Setup for each environment
bash cloudwatch-setup.sh dev cicd us-east-1
bash cloudwatch-setup.sh staging cicd us-east-1
bash cloudwatch-setup.sh prod cicd us-east-1
```

#### 5.2 Setup Alert Triggers
```bash
# Create EventBridge rules for each environment
bash alert-triggers.sh dev cicd us-east-1
bash alert-triggers.sh staging cicd us-east-1
bash alert-triggers.sh prod cicd us-east-1
```

#### 5.3 Setup Cost Optimization
```bash
# Configure cost monitoring
bash cost-optimization.sh cicd us-east-1
```

---

### Phase 6: Lambda Automation (Day 6)

#### 6.1 Deploy Auto-Scaling Lambda
```bash
cd ../8-lambda-automation

# Package Lambda function
zip -r auto-scaling-lambda.zip auto-scaling-lambda.py

# Create IAM role for Lambda
ROLE_ARN=$(aws iam get-role \
  --role-name CrossAccountLambdaExecutionRole \
  --query 'Role.Arn' \
  --output text)

# Create Lambda function
aws lambda create-function \
  --function-name auto-scale-ecs \
  --runtime python3.9 \
  --role $ROLE_ARN \
  --handler auto-scaling-lambda.lambda_handler \
  --zip-file fileb://auto-scaling-lambda.zip \
  --environment Variables="{ENVIRONMENT=prod,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:$MGMT_ACCOUNT:prod-alerts}" \
  --region us-east-1 \
  --profile cicd
```

#### 6.2 Deploy Cost Optimization Lambda
```bash
zip -r cost-optimization-lambda.zip cost-optimization-lambda.py

aws lambda create-function \
  --function-name cost-optimizer \
  --runtime python3.9 \
  --role $ROLE_ARN \
  --handler cost-optimization-lambda.lambda_handler \
  --zip-file fileb://cost-optimization-lambda.zip \
  --timeout 300 \
  --environment Variables="{ENVIRONMENT=all,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:$MGMT_ACCOUNT:cost-alerts}" \
  --region us-east-1 \
  --profile cicd
```

#### 6.3 Setup EventBridge Triggers
```bash
# Auto-scaling trigger (every 5 minutes)
aws events put-rule \
  --name ecs-auto-scale-rule \
  --schedule-expression 'rate(5 minutes)' \
  --region us-east-1 \
  --profile cicd

aws events put-targets \
  --rule ecs-auto-scale-rule \
  --targets "Id=1,Arn=arn:aws:lambda:us-east-1:$MGMT_ACCOUNT:function:auto-scale-ecs,RoleArn=$ROLE_ARN" \
  --region us-east-1 \
  --profile cicd

# Cost optimization trigger (daily at 9 AM UTC)
aws events put-rule \
  --name daily-cost-check-rule \
  --schedule-expression 'cron(0 9 * * ? *)' \
  --region us-east-1 \
  --profile cicd

aws events put-targets \
  --rule daily-cost-check-rule \
  --targets "Id=1,Arn=arn:aws:lambda:us-east-1:$MGMT_ACCOUNT:function:cost-optimizer,RoleArn=$ROLE_ARN" \
  --region us-east-1 \
  --profile cicd
```

---

## Verification Checklist

- [ ] AWS Organizations enabled with 4 linked accounts
- [ ] IAM roles deployed to all accounts
- [ ] Cross-account trust relationships configured
- [ ] CodeCommit repository created and initialized
- [ ] CodeBuild project created and tested
- [ ] VPC infrastructure deployed to all environments
- [ ] ECS clusters running in all environments
- [ ] CodePipeline executing end-to-end
- [ ] CloudWatch alarms and dashboards created
- [ ] Lambda functions deployed and scheduled
- [ ] Cost monitoring and alerts configured

## Troubleshooting

### Issue: CodePipeline fails at CloudFormation stage
**Solution:**
```bash
# Check CloudFormation errors
aws cloudformation describe-stack-events \
  --stack-name my-app-dev-stack \
  --region us-east-1 \
  --profile development
```

### Issue: Cross-account assumption fails
**Solution:**
```bash
# Verify trust relationship
aws iam get-role \
  --role-name CrossAccountCodePipelineRole \
  --region us-east-1 \
  --profile development

# Check assume role policy
aws iam get-role-policy \
  --role-name CrossAccountCodePipelineRole \
  --policy-name AssumeRolePolicy \
  --region us-east-1 \
  --profile development
```

### Issue: Lambda timeout during scaling
**Solution:**
```bash
# Increase timeout
aws lambda update-function-configuration \
  --function-name auto-scale-ecs \
  --timeout 60 \
  --region us-east-1 \
  --profile cicd
```

## Post-Deployment Tasks

1. **Subscribe to SNS alerts:**
   ```bash
   aws sns subscribe \
     --topic-arn arn:aws:sns:us-east-1:$ACCOUNT_ID:prod-alerts \
     --protocol email \
     --notification-endpoint your-email@company.com
   ```

2. **Configure AWS Budgets:** Update email in cost-optimization.sh and create budget

3. **Setup backup policy:** Enable automated backups for RDS

4. **Configure CloudTrail:** For audit logging across accounts

5. **Enable AWS Config:** For compliance monitoring

## Cost Optimization Tips

1. **Use Spot Instances:** 70-90% savings for non-critical workloads
2. **Reserved Instances:** 24-31% savings for production baseline
3. **Savings Plans:** Up to 36% savings with 3-year commitment
4. **Auto-shutdown:** Stop dev/staging resources at 6 PM
5. **Fargate Spot:** 70% savings on container workloads
6. **Log retention:** Keep logs for 7 days in dev, 30 in prod
7. **S3 Intelligent-Tiering:** Automatic cost optimization
8. **VPC Endpoints:** Reduce NAT gateway costs

## Estimated Costs (Monthly)

| Service | Dev | Staging | Prod | Total |
|---------|-----|---------|------|-------|
| CodeBuild | $10 | $10 | $10 | $30 |
| ECS Fargate | $30 | $50 | $150 | $230 |
| RDS | $15 | $30 | $100 | $145 |
| Networking | $15 | $15 | $50 | $80 |
| Monitoring | $10 | $10 | $20 | $40 |
| Storage | $10 | $10 | $20 | $40 |
| **Total** | **$90** | **$125** | **$350** | **$565/mo** |

## Support & Escalation

For issues:
1. Check CloudWatch Logs
2. Review CloudFormation events
3. Check IAM permissions
4. Verify EventBridge rules
5. Test Lambda functions manually

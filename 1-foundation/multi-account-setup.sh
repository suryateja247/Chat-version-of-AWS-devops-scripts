#!/bin/bash

################################################################################
# Multi-Account AWS Setup Script
# Purpose: Initialize AWS Organizations and create cross-account roles
# Author: DevOps Team
# Usage: bash multi-account-setup.sh
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MANAGEMENT_ACCOUNT_ID=""
ORG_NAME="MyCompanyDevOps"
REGION="us-east-1"

# Functions
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install jq."
        exit 1
    fi
    
    # Get management account ID
    MANAGEMENT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_status "Management Account ID: $MANAGEMENT_ACCOUNT_ID"
}

# Enable AWS Organizations
enable_organizations() {
    print_status "Enabling AWS Organizations..."
    
    if aws organizations describe-organization &>/dev/null; then
        print_warning "AWS Organizations already enabled"
    else
        aws organizations create-organization --feature-set ALL
        print_status "AWS Organizations enabled successfully"
    fi
}

# Create member accounts
create_accounts() {
    print_status "Creating member accounts..."
    
    local accounts=("cicd" "development" "staging" "production")
    
    for account in "${accounts[@]}"; do
        print_status "Creating $account account..."
        
        ACCOUNT_EMAIL="${account}@$(echo $ORG_NAME | tr '[:upper:]' '[:lower:]').aws"
        
        RESPONSE=$(aws organizations create-account \
            --account-name "${account}-account" \
            --email "$ACCOUNT_EMAIL" \
            --output json)
        
        REQUEST_ID=$(echo $RESPONSE | jq -r '.CreateAccountStatus.Id')
        print_status "Account creation request ID: $REQUEST_ID"
        
        # Note: Account creation is async, may take 5-10 minutes
        echo "Please note: Account creation is asynchronous and may take 5-10 minutes."
    done
}

# Create CloudFormation template for IAM roles
create_iam_template() {
    print_status "Creating IAM CloudFormation template..."
    
    cat > /tmp/iam-roles-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Cross-Account IAM Roles for Multi-Account DevOps'

Parameters:
  ManagementAccountId:
    Type: String
    Description: Management Account ID

Resources:
  # Role for CI/CD Account to assume in other accounts
  CrossAccountCodePipelineRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CrossAccountCodePipelineRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::${ManagementAccountId}:root'
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/AdministratorAccess'

  # Role for Lambda to invoke cross-account actions
  CrossAccountLambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: CrossAccountLambdaExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
      Policies:
        - PolicyName: CrossAccountAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - 'sts:AssumeRole'
                Resource: !Sub 'arn:aws:iam::*:role/CrossAccountLambdaRole'

  # Role for EC2 instances
  EC2InstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: EC2InstanceRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy'
        - 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'
      Policies:
        - PolicyName: S3Access
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - 's3:GetObject'
                  - 's3:ListBucket'
                Resource:
                  - !Sub 'arn:aws:s3:::devops-artifacts-${AWS::AccountId}'
                  - !Sub 'arn:aws:s3:::devops-artifacts-${AWS::AccountId}/*'

  EC2InstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref EC2InstanceRole

Outputs:
  CrossAccountCodePipelineRoleArn:
    Value: !GetAtt CrossAccountCodePipelineRole.Arn
    Export:
      Name: CrossAccountCodePipelineRoleArn
  
  EC2InstanceRoleArn:
    Value: !GetAtt EC2InstanceRole.Arn
    Export:
      Name: EC2InstanceRoleArn
EOF
    
    print_status "IAM template created at /tmp/iam-roles-template.yaml"
}

# Create S3 bucket for artifacts
create_artifact_bucket() {
    print_status "Creating S3 bucket for artifacts..."
    
    BUCKET_NAME="devops-artifacts-${MANAGEMENT_ACCOUNT_ID}"
    
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        print_warning "Bucket $BUCKET_NAME already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region $REGION
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$BUCKET_NAME" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        print_status "Artifact bucket created: s3://${BUCKET_NAME}"
    fi
}

# Setup AWS CLI profiles
setup_cli_profiles() {
    print_status "Setting up AWS CLI profiles..."
    
    cat > ~/.aws/config.example << 'EOF'
[default]
region = us-east-1
output = json

[profile management]
region = us-east-1
output = json
role_arn = arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/OrganizationAccountAccessRole
source_profile = default

[profile cicd]
region = us-east-1
output = json
role_arn = arn:aws:iam::CICD_ACCOUNT_ID:role/OrganizationAccountAccessRole
source_profile = default

[profile development]
region = us-east-1
output = json
role_arn = arn:aws:iam::DEV_ACCOUNT_ID:role/OrganizationAccountAccessRole
source_profile = default

[profile staging]
region = us-east-1
output = json
role_arn = arn:aws:iam::STAGING_ACCOUNT_ID:role/OrganizationAccountAccessRole
source_profile = default

[profile production]
region = us-east-1
output = json
role_arn = arn:aws:iam::PROD_ACCOUNT_ID:role/OrganizationAccountAccessRole
source_profile = default
EOF
    
    print_status "CLI profile template created at ~/.aws/config.example"
    print_warning "Please update the account IDs in ~/.aws/config.example and copy to ~/.aws/config"
}

# Main execution
main() {
    print_status "Starting multi-account AWS setup..."
    
    check_prerequisites
    enable_organizations
    # create_accounts  # Commented out - requires manual approval
    create_iam_template
    create_artifact_bucket
    setup_cli_profiles
    
    print_status "Multi-account setup completed!"
    print_status "Next steps:"
    echo "  1. Approve account creation requests in AWS Organizations console"
    echo "  2. Update CLI profiles with actual account IDs"
    echo "  3. Deploy IAM CloudFormation template to each account"
    echo "  4. Configure cross-account trust relationships"
}

main

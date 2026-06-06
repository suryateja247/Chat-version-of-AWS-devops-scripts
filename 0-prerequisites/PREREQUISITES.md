# Prerequisites for Multi-Account AWS DevOps Setup

## AWS Services Required (Cost-Effective Selection)

### 1. **Core AWS Services** ✅ (Free/Low-Cost Tier)
- **AWS CodeCommit** - Git repositories (Free tier: 5 active users)
- **AWS CodeBuild** - CI/CD builds (Free tier: 100 build minutes/month)
- **AWS CodePipeline** - Pipeline orchestration (Free tier: 1 active pipeline/month)
- **AWS CodeDeploy** - Deployment automation (Free)
- **AWS Lambda** - Serverless automation (Free tier: 1M requests/month)
- **AWS CloudWatch** - Monitoring & logs (Free tier: 5GB logs ingestion/month)
- **AWS EventBridge** - Event-driven automation (Free tier: first 10 custom events/month free)
- **AWS SNS** - Notifications (Free tier: 1,000 SMS, 100,000 email)
- **AWS Systems Manager** - Agent-based management (Free)
- **AWS IAM** - Identity & access (Free)

### 2. **Infrastructure Services** (Pay-as-you-go, optimizable)
- **AWS EC2** - Virtual machines (Use Spot instances: 70-90% discount)
- **AWS ECS/EKS** - Container orchestration (ECS is cheaper than EKS)
- **AWS RDS** - Managed databases (Use Multi-AZ only for production)
- **AWS VPC** - Networking (Free, pay for NAT gateway & data transfer)
- **AWS S3** - Storage (Free tier: 5GB storage)
- **AWS CloudFormation** - IaC orchestration (Free, pay for resources)

### 3. **Cost Optimization Services**
- **AWS Budgets** - Cost monitoring (Free)
- **AWS Cost Explorer** - Cost analysis (Free)
- **AWS Savings Plans** - Discounted instances (1-year: 19-36% savings)
- **AWS Reserved Instances** - Upfront discounts (1-year: 24-31% savings)

### 4. **Multi-Account Management**
- **AWS Organizations** - Account consolidation (Free)
- **AWS CloudTrail** - Audit logs (Free tier: 90-day history in console)
- **AWS Config** - Resource compliance (Optional, $2/rule/account/month)

## Why NOT to Use Jenkins + Nexus on EC2?

| Service | Jenkins on EC2 | AWS CodeBuild + CodeArtifact | Cost Savings |
|---------|----------------|------------------------------|---------------|
| Compute | t3.medium ($0.05/hr) | On-demand, pay per build | 95% |
| Storage | EBS + S3 | CodeArtifact (pay per GB) | 80% |
| Maintenance | Manual patching | Fully managed | $5k/yr |
| Scaling | Manual | Auto-scaling | 40% |
| **Total/Month** | ~$50-100 | ~$5-15 | **80-90%** |

## Software Prerequisites

### Local Development Machine
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Terraform (for Infrastructure as Code)
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Ansible
sudo apt-get update && sudo apt-get install -y ansible

# Install jq (JSON processor)
sudo apt-get install -y jq

# Install git
sudo apt-get install -y git
```

### AWS Accounts Structure
```
Root Account (AWS Organizations)
├── Management Account
│   ├── IAM Roles
│   ├── Organizations setup
│   └── Billing consolidation
├── CI/CD Account
│   ├── CodeCommit repositories
│   ├── CodeBuild
│   ├── CodePipeline
│   └── CodeArtifact
├── Development Account
│   ├── Dev VPC
│   ├── Dev ECS/EKS cluster
│   └── Dev RDS
├── Staging Account
│   ├── Staging VPC
│   ├── Staging ECS/EKS cluster
│   └── Staging RDS
└── Production Account
    ├── Production VPC
    ├── Production ECS/EKS cluster (Multi-AZ)
    ├── Production RDS (Multi-AZ)
    └── CloudFront CDN
```

## IAM Permissions Required

### Management Account (Root User Setup)
- Organizations:* (Enable AWS Organizations)
- IAM:* (Create cross-account roles)

### CI/CD Account
- CodeCommit:*
- CodeBuild:*
- CodePipeline:*
- CodeArtifact:*
- CodeDeploy:*
- S3:*
- Lambda:*
- CloudWatch:*
- SNS:*
- EventBridge:*
- STS:AssumeRole (for cross-account access)

### Development/Staging/Production Accounts
- EC2:*
- ECS:*
- EKS:*
- RDS:*
- VPC:*
- IAM:PassRole
- STS:AssumeRole (for cross-account access)
- CloudWatch:*
- CloudFormation:*

## Network Requirements

### AWS CodeCommit Git Access
- HTTPS: Requires AWS credentials
- SSH: Requires EC2 Key Pair or IAM SSH keys

### Cross-Account Communication
- VPC Peering or AWS Transit Gateway
- Security Groups allowing traffic
- IAM roles with cross-account trust

## Estimated Monthly Costs (for small team)

| Component | Unit Cost | Monthly Cost | Notes |
|-----------|-----------|--------------|-------|
| CodeBuild | $0.01/min | $10-20 | 20-40 builds/day |
| CodeArtifact | $0.50/GB stored | $5-10 | ~10-20 GB artifacts |
| Lambda | $0.20/1M requests | $1-5 | Automation tasks |
| EC2 (Spot) | $0.015/hr | $100-200 | Dev/Test instances |
| ECS on EC2 | Included in EC2 | Included | Better than EKS |
| RDS (Dev) | $0.02/hr | $15 | t3.micro free for 12 months |
| CloudWatch | Logs ingestion | $5-15 | 5GB/month baseline |
| SNS | Per notification | $1-2 | Alerts and notifications |
| Data Transfer | $0.09/GB out | $5-20 | Between regions |
| **TOTAL** | | **$142-282/month** | ⬅️ Very cost-effective |

## Next Steps

1. Create AWS Organization (free)
2. Create 4 linked accounts (dev, staging, prod, cicd)
3. Set up cross-account IAM roles
4. Configure AWS CLI with multi-account profiles
5. Set up VPCs and networking
6. Deploy CI/CD pipeline
7. Configure monitoring and alerts
8. Implement cost optimization

## Recommended Reading

- [AWS Well-Architected Framework - Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)
- [AWS Organizations Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices.html)
- [AWS CodePipeline Best Practices](https://docs.aws.amazon.com/codepipeline/latest/userguide/best-practices.html)
- [ECS vs EKS: Cost Comparison](https://aws.amazon.com/blogs/containers/)

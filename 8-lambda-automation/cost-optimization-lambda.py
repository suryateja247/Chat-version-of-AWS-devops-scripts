import boto3
import json
import os
from datetime import datetime

"""
Lambda Function: Cost Optimization
Purpose: Identify and report unused resources, recommend optimizations
Trigger: EventBridge rule (daily at 9 AM)
"""

ec2 = boto3.client('ec2')
rds = boto3.client('rds')
s3 = boto3.client('s3')
ce = boto3.client('ce')  # Cost Explorer
sns = boto3.client('sns')


def lambda_handler(event, context):
    """
    Main handler for cost optimization analysis
    """
    environment = os.environ.get('ENVIRONMENT', 'all')
    
    try:
        findings = []
        
        # Check for unused EC2 instances
        ec2_findings = check_unused_ec2_instances()
        findings.extend(ec2_findings)
        
        # Check for unattached EBS volumes
        ebs_findings = check_unattached_ebs()
        findings.extend(ebs_findings)
        
        # Check for unused RDS instances
        rds_findings = check_unused_rds_instances()
        findings.extend(rds_findings)
        
        # Check for empty S3 buckets
        s3_findings = check_empty_s3_buckets()
        findings.extend(s3_findings)
        
        # Get cost summary
        cost_summary = get_cost_summary()
        
        # Prepare report
        report = prepare_report(findings, cost_summary, environment)
        
        # Send report
        send_report(report)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis complete',
                'findingsCount': len(findings),
                'timestamp': datetime.now().isoformat()
            })
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def check_unused_ec2_instances():
    """
    Identify EC2 instances with low CPU utilization
    """
    findings = []
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        response = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                
                # Get average CPU over past 7 days
                stats = cloudwatch.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName='CPUUtilization',
                    Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                    StartTime=datetime.utcnow().replace(day=datetime.utcnow().day - 7),
                    EndTime=datetime.utcnow(),
                    Period=86400,
                    Statistics=['Average']
                )
                
                if stats['Datapoints']:
                    avg_cpu = sum([d['Average'] for d in stats['Datapoints']]) / len(stats['Datapoints'])
                    
                    if avg_cpu < 5:
                        findings.append({
                            'type': 'UnusedEC2',
                            'resourceId': instance_id,
                            'description': f'EC2 instance {instance_id} has {avg_cpu:.2f}% avg CPU over 7 days',
                            'recommendation': 'Consider stopping or terminating this instance',
                            'estimatedSavings': instance['InstanceType']  # Would need price lookup
                        })
    
    except Exception as e:
        print(f"Error checking EC2: {str(e)}")
    
    return findings


def check_unattached_ebs():
    """
    Find unattached EBS volumes
    """
    findings = []
    
    try:
        response = ec2.describe_volumes(Filters=[{'Name': 'status', 'Values': ['available']}])
        
        for volume in response['Volumes']:
            findings.append({
                'type': 'UnattachedEBS',
                'resourceId': volume['VolumeId'],
                'description': f"Unattached EBS volume {volume['VolumeId']} ({volume['Size']} GB)",
                'recommendation': 'Delete unused volumes to reduce costs',
                'estimatedSavings': f"${volume['Size'] * 0.10}/month"  # ~$0.10 per GB
            })
    
    except Exception as e:
        print(f"Error checking EBS: {str(e)}")
    
    return findings


def check_unused_rds_instances():
    """
    Identify unused RDS instances
    """
    findings = []
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        response = rds.describe_db_instances()
        
        for db in response['DBInstances']:
            db_id = db['DBInstanceIdentifier']
            
            # Check connection count
            stats = cloudwatch.get_metric_statistics(
                Namespace='AWS/RDS',
                MetricName='DatabaseConnections',
                Dimensions=[{'Name': 'DBInstanceIdentifier', 'Value': db_id}],
                StartTime=datetime.utcnow().replace(day=datetime.utcnow().day - 7),
                EndTime=datetime.utcnow(),
                Period=86400,
                Statistics=['Maximum']
            )
            
            if stats['Datapoints'] and all(d['Maximum'] == 0 for d in stats['Datapoints']):
                findings.append({
                    'type': 'UnusedRDS',
                    'resourceId': db_id,
                    'description': f"RDS instance {db_id} has 0 connections over 7 days",
                    'recommendation': 'Consider stopping or deleting this database',
                    'estimatedSavings': f"${db['DBInstanceClass']}"  # Would need price lookup
                })
    
    except Exception as e:
        print(f"Error checking RDS: {str(e)}")
    
    return findings


def check_empty_s3_buckets():
    """
    Find empty S3 buckets
    """
    findings = []
    
    try:
        response = s3.list_buckets()
        
        for bucket in response['Buckets']:
            bucket_name = bucket['Name']
            
            # Check bucket size
            try:
                objects = s3.list_objects_v2(Bucket=bucket_name, MaxKeys=1)
                
                if 'Contents' not in objects:
                    findings.append({
                        'type': 'EmptyS3Bucket',
                        'resourceId': bucket_name,
                        'description': f"S3 bucket {bucket_name} is empty",
                        'recommendation': 'Delete unused buckets',
                        'estimatedSavings': 'Storage costs reduced'
                    })
            except:
                pass
    
    except Exception as e:
        print(f"Error checking S3: {str(e)}")
    
    return findings


def get_cost_summary():
    """
    Get cost summary from Cost Explorer
    """
    try:
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': (datetime.utcnow().replace(day=1)).strftime('%Y-%m-%d'),
                'End': datetime.utcnow().strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response
    except:
        return None


def prepare_report(findings, cost_summary, environment):
    """
    Prepare optimization report
    """
    report = f"""
    === AWS Cost Optimization Report ===
    Generated: {datetime.now().isoformat()}
    Environment: {environment}
    
    === Findings ({len(findings)} issues found) ===
    """
    
    for finding in findings:
        report += f"""
    
    [{finding['type']}]
    Resource: {finding['resourceId']}
    Issue: {finding['description']}
    Recommendation: {finding['recommendation']}
    Potential Savings: {finding.get('estimatedSavings', 'TBD')}
    """
    
    return report


def send_report(report):
    """
    Send report via SNS
    """
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if topic_arn:
        sns.publish(
            TopicArn=topic_arn,
            Subject='Daily Cost Optimization Report',
            Message=report
        )


if __name__ == "__main__":
    lambda_handler({}, None)

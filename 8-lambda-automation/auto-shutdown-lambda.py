#!/bin/bash

################################################################################
# Auto-Shutdown Lambda for Non-Production Resources
# Purpose: Automatically shut down development/staging resources at night
# Trigger: EventBridge rule (daily at 6 PM)
################################################################################

import boto3
import os
from datetime import datetime

ec2 = boto3.client('ec2')
rds = boto3.client('rds')
ecs = boto3.client('ecs')

def lambda_handler(event, context):
    """
    Auto-shutdown handler for non-production resources
    """
    environment = os.environ.get('ENVIRONMENT', 'dev')
    
    if environment == 'prod':
        print("Production environment - skipping shutdown")
        return
    
    try:
        # Stop EC2 instances
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']},
                {'Name': 'tag:Environment', 'Values': [environment]},
                {'Name': 'tag:AutoShutdown', 'Values': ['true']}
            ]
        )
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                ec2.stop_instances(InstanceIds=[instance['InstanceId']])
                print(f"Stopped EC2 instance: {instance['InstanceId']}")
        
        # Stop RDS instances (if not multi-AZ)
        dbs = rds.describe_db_instances()
        for db in dbs['DBInstances']:
            if (db['DBInstanceIdentifier'].startswith(environment) and 
                not db['MultiAZ']):
                rds.stop_db_instance(DBInstanceIdentifier=db['DBInstanceIdentifier'])
                print(f"Stopped RDS instance: {db['DBInstanceIdentifier']}")
        
        # Scale down ECS service
        ecs.update_service(
            cluster=f"{environment}-cluster",
            service=f"{environment}-service",
            desiredCount=0
        )
        print(f"Scaled down ECS service to 0 tasks")
        
        return {
            'statusCode': 200,
            'message': f'Successfully shut down {environment} resources'
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }


import boto3
import json
import os
from datetime import datetime, timedelta

"""
Lambda Function: Auto-Scale ECS Service
Purpose: Dynamically scale ECS services based on time of day and cost optimization
Trigger: EventBridge rule (scheduled or metric-based)
"""

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')
autoschaling = boto3.client('application-autoscaling')


def lambda_handler(event, context):
    """
    Main Lambda handler for auto-scaling logic
    """
    environment = os.environ.get('ENVIRONMENT', 'dev')
    cluster_name = f"{environment}-cluster"
    service_name = f"{environment}-service"
    
    try:
        # Get current service state
        response = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )
        
        service = response['services'][0]
        current_count = service['desiredCount']
        running_count = service['runningCount']
        
        print(f"Current state - Desired: {current_count}, Running: {running_count}")
        
        # Get CPU metrics
        cpu_utilization = get_cpu_utilization(cluster_name, service_name)
        print(f"CPU Utilization: {cpu_utilization}%")
        
        # Determine desired count based on time of day and metrics
        new_count = calculate_desired_count(
            environment=environment,
            current_count=current_count,
            cpu_utilization=cpu_utilization
        )
        
        # Scale if needed
        if new_count != current_count:
            print(f"Scaling from {current_count} to {new_count} tasks")
            ecs.update_service(
                cluster=cluster_name,
                service=service_name,
                desiredCount=new_count
            )
            
            # Log scaling action
            log_scaling_action(environment, current_count, new_count)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Service scaled from {current_count} to {new_count} tasks',
                    'environment': environment,
                    'timestamp': datetime.now().isoformat()
                })
            }
        else:
            print("No scaling needed")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No scaling needed',
                    'environment': environment,
                    'currentCount': current_count
                })
            }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        send_alert(f"Auto-scaling failed for {environment}: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def get_cpu_utilization(cluster_name, service_name):
    """
    Get average CPU utilization for the past 5 minutes
    """
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ECS',
        MetricName='CPUUtilization',
        Dimensions=[
            {'Name': 'ClusterName', 'Value': cluster_name},
            {'Name': 'ServiceName', 'Value': service_name}
        ],
        StartTime=datetime.utcnow() - timedelta(minutes=5),
        EndTime=datetime.utcnow(),
        Period=300,
        Statistics=['Average']
    )
    
    if response['Datapoints']:
        return response['Datapoints'][0]['Average']
    return 0


def calculate_desired_count(environment, current_count, cpu_utilization):
    """
    Calculate desired task count based on environment and metrics
    """
    hour = datetime.now().hour
    is_business_hours = 8 <= hour < 18  # 8 AM to 6 PM
    is_weekend = datetime.now().weekday() >= 5  # Saturday = 5, Sunday = 6
    
    # Scale-down logic for cost optimization
    if environment == 'dev':
        if is_weekend or hour < 8 or hour > 18:
            return 1  # Minimum 1 task at night/weekends
        else:
            return 2  # 2 tasks during business hours
    
    elif environment == 'staging':
        if hour < 8 or hour > 18:
            return 1  # 1 task at night
        else:
            return 2  # 2 tasks during business hours
    
    elif environment == 'prod':
        # Production: scale based on CPU
        if cpu_utilization > 80:
            return min(current_count + 2, 10)  # Scale up, max 10
        elif cpu_utilization < 30 and current_count > 3:
            return current_count - 1  # Scale down gradually
        else:
            return max(current_count, 3)  # Minimum 3 for HA
    
    return current_count


def log_scaling_action(environment, old_count, new_count):
    """
    Log scaling action to CloudWatch
    """
    cloudwatch.put_metric_data(
        Namespace=f'Custom/{environment}',
        MetricData=[
            {
                'MetricName': 'TaskScalingAction',
                'Value': new_count - old_count,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            }
        ]
    )


def send_alert(message):
    """
    Send alert via SNS
    """
    sns = boto3.client('sns')
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if topic_arn:
        sns.publish(
            TopicArn=topic_arn,
            Subject='ECS Auto-Scaling Alert',
            Message=message
        )


if __name__ == "__main__":
    # For local testing
    test_event = {
        'detail-type': 'Scheduled Event',
        'source': 'aws.events'
    }
    lambda_handler(test_event, None)

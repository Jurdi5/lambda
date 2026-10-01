import boto3
import re
import uuid

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('LogEntries')
s3 = boto3.client('s3')

LOG_PATTERN = re.compile(
    r'^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\w+)\[(\d+)\]:\s+(.*)$'
)

def lambda_handler(event, context):
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']

    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj['Body'].read().decode('utf-8')

    count = 0
    with table.batch_writer() as batch:
        for line in content.splitlines():
            if not line.strip():
                continue

            match = LOG_PATTERN.match(line)
            if match:
                timestamp, hostname, program, pid, message = match.groups()
            else:
                timestamp, hostname, program, pid, message = '', '', '', '', line

            batch.put_item(Item={
                'source': 'openssh',
                'log_id': f"{key}#{uuid.uuid4()}",
                'timestamp': timestamp,
                'hostname': hostname,
                'program': program,
                'pid': pid,
                'log': message,
                'batch_file': key
            })
            count += 1

    return {
        'statusCode': 200,
        'body': f'Insertados {count} registros de {key} en DynamoDB'
    }
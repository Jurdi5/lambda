import boto3
import csv
import io
import re
import os

s3 = boto3.client('s3')

LOG_PATTERN = re.compile(
    r'^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\w+)\[(\d+)\]:\s+(.*)$'
)

def lambda_handler(event, context):
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = record['s3']['object']['key']  # input/openssh-xxxx.log

    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj['Body'].read().decode('utf-8')

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['timestamp', 'hostname', 'program', 'pid', 'log'])

    for line in content.splitlines():
        if not line.strip():
            continue
        match = LOG_PATTERN.match(line)
        if match:
            timestamp, hostname, program, pid, message = match.groups()
            writer.writerow([timestamp, hostname, program, pid, message])
        else:
            # línea que no matchea el formato esperado
            writer.writerow(['', '', '', '', line])

    filename = os.path.basename(key)  # openssh-xxxx.log
    csv_key = 'output/' + filename.replace('.log', '.csv')

    s3.put_object(
        Bucket=bucket,
        Key=csv_key,
        Body=output.getvalue().encode('utf-8')
    )

    return {
        'statusCode': 200,
        'body': f'Procesado {key} -> {csv_key}'
    }
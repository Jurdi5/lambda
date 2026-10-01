import re
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client('s3')

LOG_PATTERN = re.compile(r'^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+')


def lambda_handler(event, context):
    """Descarga un batch de S3 y lo regresa separado en lineas.

    La clasificacion (normal / sospechosa) la hace la maquina de estados.
    """
    bucket = event['bucket']
    key = unquote_plus(event['key'])

    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj['Body'].read().decode('utf-8', errors='replace')
    # Hora real en que llego el batch a S3 (sort key del GSI de Logs)
    last_modified = obj['LastModified'].strftime('%Y-%m-%dT%H:%M:%SZ')

    lines = []
    for index, line in enumerate(content.splitlines()):
        if not line.strip():
            continue

        match = LOG_PATTERN.match(line)
        timestamp, host = match.groups() if match else ('', '')

        lines.append({
            'id': f'{key}#{index:05d}',
            'timestamp': timestamp,
            'host': host,
            'log': line,
            'last_modified': last_modified,
        })

    print(f'{key}: {len(lines)} lineas')
    return {'bucket': bucket, 'key': key, 'count': len(lines), 'lines': lines}

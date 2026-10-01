import json
import os
from decimal import Decimal

import boto3

TABLE_NAME = os.environ.get('TABLE_NAME', 'SecurityAlerts')
FIELDS = ('id', 'timestamp', 'host', 'log', 'severity')

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)


def _default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f'tipo no serializable: {type(value).__name__}')


def _response(status, body):
    return {
        'statusCode': status,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body, default=_default),
    }


def lambda_handler(event, context):
    try:
        items = []
        kwargs = {}
        while True:
            page = table.scan(**kwargs)
            items.extend(page.get('Items', []))
            last_key = page.get('LastEvaluatedKey')
            if not last_key:
                break
            kwargs['ExclusiveStartKey'] = last_key

        alerts = [{f: item.get(f) for f in FIELDS} for item in items]
        alerts.sort(key=lambda a: str(a.get('timestamp') or ''), reverse=True)

        return _response(200, {'count': len(alerts), 'alerts': alerts})
    except Exception as e:
        print(f'error leyendo {TABLE_NAME}: {e}')
        return _response(500, {'message': 'error al leer alertas'})

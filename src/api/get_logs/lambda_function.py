import json
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ.get('TABLE_NAME', 'Logs')
INDEX_NAME = os.environ.get('INDEX_NAME', 'LastModifiedIndex')
GSI_PK_NAME = os.environ.get('GSI_PK_NAME', 'gsi_pk')
GSI_PK_VALUE = os.environ.get('GSI_PK_VALUE', 'LOG')

DEFAULT_TOP = 10
MIN_TOP = 1
MAX_TOP = 1000

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


def _parse_top(event):
    params = event.get('queryStringParameters') or {}
    raw = params.get('top')
    if raw is None or raw == '':
        return DEFAULT_TOP
    try:
        top = int(raw)
    except (TypeError, ValueError):
        return None
    if top < MIN_TOP or top > MAX_TOP:
        return None
    return top


def lambda_handler(event, context):
    top = _parse_top(event or {})
    if top is None:
        return _response(400, {
            'message': f'top debe ser un entero entre {MIN_TOP} y {MAX_TOP}'
        })

    try:
        items = []
        kwargs = {
            'IndexName': INDEX_NAME,
            'KeyConditionExpression': Key(GSI_PK_NAME).eq(GSI_PK_VALUE),
            'ScanIndexForward': False,
        }
        while len(items) < top:
            kwargs['Limit'] = top - len(items)
            page = table.query(**kwargs)
            items.extend(page.get('Items', []))
            last_key = page.get('LastEvaluatedKey')
            if not last_key:
                break
            kwargs['ExclusiveStartKey'] = last_key

        return _response(200, {'count': len(items), 'logs': items[:top]})
    except Exception as e:
        print(f'error consultando {TABLE_NAME}/{INDEX_NAME}: {e}')
        return _response(500, {'message': 'error al leer logs'})

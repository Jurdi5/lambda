#!/bin/bash
# Crea las tablas Logs (con GSI LastModifiedIndex) y SecurityAlerts.
# Si una tabla ya existe la deja como esta.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

table_exists() {
  aws dynamodb describe-table --table-name "$1" >/dev/null 2>&1
}

if table_exists "$LOGS_TABLE"; then
  echo "Tabla $LOGS_TABLE ya existe"
else
  echo "Creando tabla $LOGS_TABLE con GSI $LOGS_INDEX..."
  aws dynamodb create-table \
    --table-name "$LOGS_TABLE" \
    --attribute-definitions \
        AttributeName=id,AttributeType=S \
        AttributeName=gsi_pk,AttributeType=S \
        AttributeName=last_modified,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --global-secondary-indexes "[{
        \"IndexName\": \"${LOGS_INDEX}\",
        \"KeySchema\": [
          {\"AttributeName\": \"gsi_pk\", \"KeyType\": \"HASH\"},
          {\"AttributeName\": \"last_modified\", \"KeyType\": \"RANGE\"}
        ],
        \"Projection\": {\"ProjectionType\": \"ALL\"}
      }]" \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi

if table_exists "$ALERTS_TABLE"; then
  echo "Tabla $ALERTS_TABLE ya existe"
else
  echo "Creando tabla $ALERTS_TABLE..."
  aws dynamodb create-table \
    --table-name "$ALERTS_TABLE" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi

aws dynamodb wait table-exists --table-name "$LOGS_TABLE"
aws dynamodb wait table-exists --table-name "$ALERTS_TABLE"
echo "Tablas $LOGS_TABLE y $ALERTS_TABLE activas"

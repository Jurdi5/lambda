#!/bin/bash
# Teardown general: borra todos los recursos de la practica.
# No falla si algun recurso ya no existe.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# API Gateway + Lambdas de consulta (get-alerts, get-logs)
bash "$SCRIPT_DIR/teardown_api.sh"

echo "Borrando regla de EventBridge $EVENT_RULE_NAME..."
aws events remove-targets --rule "$EVENT_RULE_NAME" --ids log-pipeline >/dev/null 2>&1 || true
aws events delete-rule --name "$EVENT_RULE_NAME" >/dev/null 2>&1 || true

STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
echo "Borrando maquina de estados $STATE_MACHINE_NAME..."
aws stepfunctions delete-state-machine --state-machine-arn "$STATE_MACHINE_ARN" >/dev/null 2>&1 || true

# log-processor es la Lambda de la version anterior (Parte 2)
for fn in "$SPLIT_FUNCTION" log-processor; do
  if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    echo "Borrando Lambda $fn..."
    aws lambda delete-function --function-name "$fn" || true
  fi
done

# LogEntries es la tabla de la version anterior (Parte 2)
for table in "$LOGS_TABLE" "$ALERTS_TABLE" LogEntries; do
  if aws dynamodb describe-table --table-name "$table" >/dev/null 2>&1; then
    echo "Borrando tabla $table..."
    aws dynamodb delete-table --table-name "$table" >/dev/null || true
    aws dynamodb wait table-not-exists --table-name "$table" || true
  fi
done

if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  echo "Vaciando y borrando bucket $BUCKET_NAME..."
  aws s3 rb "s3://$BUCKET_NAME" --force >/dev/null || true
fi

rm -rf "$BUILD_DIR"
echo
echo "Teardown terminado"

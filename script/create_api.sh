#!/bin/bash
# Crea (o recrea) el HTTP API "logging-system-api" con las Lambdas de consulta:
#   GET /alerts -> get-alerts (Scan de SecurityAlerts)
#   GET /logs   -> get-logs   (Query al GSI LastModifiedIndex de Logs)
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/src/api"
BUILD_DIR="$ROOT_DIR/build"

API_NAME="logging-system-api"
RUNTIME="python3.12"
TIMEOUT=15
STATEMENT_ID="apigateway-invoke"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"

echo "Cuenta: $ACCOUNT_ID | Region: $AWS_REGION"

mkdir -p "$BUILD_DIR"

# deploy_lambda <nombre> <carpeta en src/api> <variables de entorno>
deploy_lambda() {
  local name="$1" dir="$2" env_vars="$3"
  local zip_file="$BUILD_DIR/${name}.zip"

  rm -f "$zip_file"
  zip -j -q "$zip_file" "$SRC_DIR/$dir/lambda_function.py"

  if aws lambda get-function --function-name "$name" >/dev/null 2>&1; then
    echo "Actualizando Lambda $name..."
    aws lambda update-function-code \
      --function-name "$name" \
      --zip-file "fileb://$zip_file" >/dev/null
    aws lambda wait function-updated --function-name "$name"

    aws lambda update-function-configuration \
      --function-name "$name" \
      --runtime "$RUNTIME" \
      --role "$ROLE_ARN" \
      --handler lambda_function.lambda_handler \
      --timeout "$TIMEOUT" \
      --environment "Variables={${env_vars}}" >/dev/null
    aws lambda wait function-updated --function-name "$name"
  else
    echo "Creando Lambda $name..."
    aws lambda create-function \
      --function-name "$name" \
      --runtime "$RUNTIME" \
      --role "$ROLE_ARN" \
      --handler lambda_function.lambda_handler \
      --timeout "$TIMEOUT" \
      --environment "Variables={${env_vars}}" \
      --zip-file "fileb://$zip_file" >/dev/null
    aws lambda wait function-active-v2 --function-name "$name"
  fi
}

deploy_lambda "get-alerts" "get_alerts" "TABLE_NAME=SecurityAlerts"
deploy_lambda "get-logs" "get_logs" \
  "TABLE_NAME=Logs,INDEX_NAME=LastModifiedIndex,GSI_PK_NAME=gsi_pk,GSI_PK_VALUE=LOG"

# Si ya existe el API se borra para crearlo limpio
for old_id in $(aws apigatewayv2 get-apis \
    --query "Items[?Name=='${API_NAME}'].ApiId" --output text); do
  [ "$old_id" = "None" ] && continue
  echo "Borrando API existente $old_id..."
  aws apigatewayv2 delete-api --api-id "$old_id"
done

echo "Creando HTTP API $API_NAME..."
read -r API_ID API_ENDPOINT < <(aws apigatewayv2 create-api \
  --name "$API_NAME" \
  --protocol-type HTTP \
  --query "[ApiId,ApiEndpoint]" --output text)

# add_route <nombre lambda> <path>
add_route() {
  local name="$1" path="$2"
  local function_arn="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${name}"

  local integration_id
  integration_id="$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$function_arn" \
    --payload-format-version 2.0 \
    --query IntegrationId --output text)"

  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "GET ${path}" \
    --target "integrations/${integration_id}" >/dev/null

  aws lambda remove-permission \
    --function-name "$name" \
    --statement-id "$STATEMENT_ID" >/dev/null 2>&1 || true

  aws lambda add-permission \
    --function-name "$name" \
    --statement-id "$STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*${path}" >/dev/null

  echo "Ruta GET ${path} -> ${name}"
}

add_route "get-alerts" "/alerts"
add_route "get-logs" "/logs"

aws apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --auto-deploy >/dev/null

echo
echo "API lista: $API_ENDPOINT"
echo
echo "Pruebas:"
echo "  curl -s \"$API_ENDPOINT/alerts\""
echo "  curl -s \"$API_ENDPOINT/logs\""
echo "  curl -s \"$API_ENDPOINT/logs?top=5\""

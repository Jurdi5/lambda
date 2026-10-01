#!/bin/bash
# Borra el HTTP API "logging-system-api" y las Lambdas get-alerts / get-logs.
# No falla si algun recurso ya no existe.
set -uo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_NAME="logging-system-api"

api_ids="$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='${API_NAME}'].ApiId" --output text 2>/dev/null || true)"

found_api=false
for api_id in $api_ids; do
  [ "$api_id" = "None" ] && continue
  found_api=true
  echo "Borrando API $API_NAME ($api_id)..."
  aws apigatewayv2 delete-api --api-id "$api_id" || true
done
$found_api || echo "API $API_NAME no existe, nada que borrar"

for fn in get-alerts get-logs; do
  if aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    echo "Borrando Lambda $fn..."
    aws lambda delete-function --function-name "$fn" || true
  else
    echo "Lambda $fn no existe, nada que borrar"
  fi
done

rm -rf "$ROOT_DIR/build"
echo "Teardown del API terminado"

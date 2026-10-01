#!/bin/bash
# Crea toda la infraestructura en orden: tablas, pipeline (S3, Lambda,
# Step Functions, EventBridge) y API Gateway.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== 1/3 DynamoDB =="
bash "$SCRIPT_DIR/create_tables.sh"

echo
echo "== 2/3 S3 + Lambda + Step Functions + EventBridge =="
bash "$SCRIPT_DIR/create_pipeline.sh"

echo
echo "== 3/3 API Gateway =="
bash "$SCRIPT_DIR/create_api.sh"

echo
echo "Infraestructura lista. Para enviar logs: ./script/start_logging.sh 30"

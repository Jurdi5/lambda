#!/bin/bash
# Teardown general de la practica.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# API Gateway + Lambdas de consulta (get-alerts, get-logs)
bash "$SCRIPT_DIR/teardown_api.sh"

# TODO(equipo): agregar el borrado del resto de los recursos:
#   - Step Functions
#   - Lambdas de procesamiento
#   - Tablas DynamoDB (Logs, SecurityAlerts, LogEntries)
#   - Bucket S3 (vaciarlo antes de borrarlo)

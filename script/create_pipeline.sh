#!/bin/bash
# Crea el bucket S3, la Lambda split-batch, la maquina de estados log-pipeline
# y la regla de EventBridge que la dispara cuando llega un batch a input/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

echo "Cuenta: $ACCOUNT_ID | Region: $AWS_REGION | Bucket: $BUCKET_NAME"
mkdir -p "$BUILD_DIR"

# --- S3 ---------------------------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  echo "Bucket $BUCKET_NAME ya existe"
else
  echo "Creando bucket $BUCKET_NAME..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
  aws s3api wait bucket-exists --bucket "$BUCKET_NAME"
fi

# Manda los eventos del bucket a EventBridge
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration '{"EventBridgeConfiguration": {}}'

# --- Lambda split-batch -----------------------------------------------------
ZIP_FILE="$BUILD_DIR/${SPLIT_FUNCTION}.zip"
rm -f "$ZIP_FILE"
zip -j -q "$ZIP_FILE" "$ROOT_DIR/src/split_batch/lambda_function.py"

if aws lambda get-function --function-name "$SPLIT_FUNCTION" >/dev/null 2>&1; then
  echo "Actualizando Lambda $SPLIT_FUNCTION..."
  aws lambda update-function-code \
    --function-name "$SPLIT_FUNCTION" \
    --zip-file "fileb://$ZIP_FILE" >/dev/null
  aws lambda wait function-updated --function-name "$SPLIT_FUNCTION"
  aws lambda update-function-configuration \
    --function-name "$SPLIT_FUNCTION" \
    --runtime python3.12 \
    --role "$ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --timeout 30 >/dev/null
  aws lambda wait function-updated --function-name "$SPLIT_FUNCTION"
else
  echo "Creando Lambda $SPLIT_FUNCTION..."
  aws lambda create-function \
    --function-name "$SPLIT_FUNCTION" \
    --runtime python3.12 \
    --role "$ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --timeout 30 \
    --zip-file "fileb://$ZIP_FILE" >/dev/null
  aws lambda wait function-active-v2 --function-name "$SPLIT_FUNCTION"
fi

SPLIT_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${SPLIT_FUNCTION}"

# --- Step Functions ---------------------------------------------------------
DEFINITION_FILE="$BUILD_DIR/log_pipeline.asl.json"
sed \
  -e "s|__SPLIT_FUNCTION_ARN__|${SPLIT_ARN}|g" \
  -e "s|__LOGS_TABLE__|${LOGS_TABLE}|g" \
  -e "s|__ALERTS_TABLE__|${ALERTS_TABLE}|g" \
  "$ROOT_DIR/statemachine/log_pipeline.asl.json" > "$DEFINITION_FILE"

STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"

if aws stepfunctions describe-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" >/dev/null 2>&1; then
  echo "Actualizando maquina de estados $STATE_MACHINE_NAME..."
  aws stepfunctions update-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --definition "file://$DEFINITION_FILE" \
    --role-arn "$ROLE_ARN" >/dev/null
else
  echo "Creando maquina de estados $STATE_MACHINE_NAME..."
  aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --type STANDARD \
    --definition "file://$DEFINITION_FILE" \
    --role-arn "$ROLE_ARN" >/dev/null
fi

# --- EventBridge: S3 Object Created en input/ -> Step Functions --------------
EVENT_PATTERN="$(cat <<EOF
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": { "name": ["${BUCKET_NAME}"] },
    "object": { "key": [{ "prefix": "${INPUT_PREFIX}" }] }
  }
}
EOF
)"

echo "Creando regla de EventBridge $EVENT_RULE_NAME..."
aws events put-rule \
  --name "$EVENT_RULE_NAME" \
  --event-pattern "$EVENT_PATTERN" \
  --state ENABLED >/dev/null

aws events put-targets \
  --rule "$EVENT_RULE_NAME" \
  --targets "Id=log-pipeline,Arn=${STATE_MACHINE_ARN},RoleArn=${ROLE_ARN}" >/dev/null

echo
echo "Pipeline listo"
echo "  Bucket:            s3://${BUCKET_NAME}/${INPUT_PREFIX}"
echo "  Lambda:            ${SPLIT_FUNCTION}"
echo "  Maquina de estados: ${STATE_MACHINE_NAME}"
echo "  Regla EventBridge: ${EVENT_RULE_NAME}"

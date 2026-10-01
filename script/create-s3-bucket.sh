#!/bin/bash
BUCKET_NAME="logging-test-team8"
REGION="us-east-1"

aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
aws s3api put-object --bucket "$BUCKET_NAME" --key "input/"
aws s3api put-object --bucket "$BUCKET_NAME" --key "output/"

TABLE_NAME="LogEntries"

aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions \
      AttributeName=source,AttributeType=S \
      AttributeName=log_id,AttributeType=S \
  --key-schema \
      AttributeName=source,KeyType=HASH \
      AttributeName=log_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

echo "Esperando a que la tabla $TABLE_NAME esté activa..."
aws dynamodb wait table-exists --table-name "$TABLE_NAME"
echo "Tabla $TABLE_NAME creada y activa"

echo "Bucket $BUCKET_NAME creado con carpetas input/ y output/"
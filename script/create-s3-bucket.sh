#!/bin/bash
BUCKET_NAME="logging-test-team8"
REGION="us-east-1"

aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
aws s3api put-object --bucket "$BUCKET_NAME" --key "input/"
aws s3api put-object --bucket "$BUCKET_NAME" --key "output/"

echo "Bucket $BUCKET_NAME creado con carpetas input/ y output/"
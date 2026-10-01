# lambda

## Arquitectura (Parte 2)

El sistema ahora escribe los logs procesados directamente en DynamoDB en vez de generar CSV en S3.

- **Tabla**: `LogEntries`
  - Partition key: `source` (siempre "openssh")
  - Sort key: `log_id` (único por línea de log)

## Cómo reproducir

1. `./script/create-s3-bucket.sh` — crea el bucket S3 y la tabla DynamoDB
2. `cd src/logging-system && zip function.zip lambda_function.py && cd ../..`
3. `aws lambda create-function --function-name log-processor --runtime python3.12 --role arn:aws:iam::<ACCOUNT_ID>:role/LabRole --handler lambda_function.lambda_handler --zip-file fileb://src/logging-system/function.zip --timeout 30`
4. `aws lambda add-permission --function-name log-processor --statement-id s3invoke --action "lambda:InvokeFunction" --principal s3.amazonaws.com --source-arn arn:aws:s3:::<BUCKET_NAME> --source-account <ACCOUNT_ID>`
5. `aws s3api put-bucket-notification-configuration --bucket <BUCKET_NAME> --notification-configuration '...'`
6. `bash script/send-log.sh batches <BUCKET_NAME> 60`

## Validar en consola

DynamoDB → Tables → LogEntries → Explore table items → Query, partition key `source = openssh`. El conteo de items debe ir subiendo con cada batch recibido.
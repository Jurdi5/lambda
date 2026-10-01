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

## API Gateway (consultas)

HTTP API `logging-system-api` (API Gateway v2) con una Lambda por endpoint.

| Método | Ruta | Lambda | Descripción |
|--------|------|--------|-------------|
| GET | `/alerts` | `get-alerts` | Todas las alertas de `SecurityAlerts` (id, timestamp, host, log, severity), ordenadas por timestamp desc |
| GET | `/logs?top=N` | `get-logs` | Últimos N logs de `Logs` vía Query al GSI `LastModifiedIndex` (`ScanIndexForward=False`, `Limit=N`). `top` default 10, rango 1–1000; fuera de rango responde 400 |

### Esquema de tablas esperado

Las tablas las crea otra parte del sistema; el API solo las lee.

- **SecurityAlerts**
  - Partition key: `id` (S)
  - Atributos: `id`, `timestamp`, `host`, `log`, `severity`
- **Logs**
  - Partition key: `id` (S)
  - Atributos: `id`, `timestamp`, `host`, `log`, `gsi_pk` (siempre `"LOG"`), `last_modified` (LastModified del objeto S3, ISO 8601)
  - GSI `LastModifiedIndex`: partition key `gsi_pk`, sort key `last_modified`

### Crear

```bash
./script/create_api.sh
```

Empaqueta las Lambdas en `build/`, crea o actualiza `get-alerts` y `get-logs` (python3.12, rol `LabRole`), recrea el API, sus rutas, permisos y el stage `$default` con auto-deploy. Al final imprime la URL del API.

### Probar

```bash
curl -s "https://<API_ID>.execute-api.us-east-1.amazonaws.com/alerts"
curl -s "https://<API_ID>.execute-api.us-east-1.amazonaws.com/logs?top=5"
```

### Eliminar

```bash
./script/teardown_api.sh
```

Borra el API, las Lambdas `get-alerts` / `get-logs` y la carpeta `build/`. `./script/teardown.sh` también lo llama.

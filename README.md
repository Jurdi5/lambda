# Logging System

Práctica 2 de Desarrollo en la Nube (ITESO). Sistema serverless en AWS que ingiere logs de servidores (OpenSSH de [loghub](https://github.com/logpai/loghub)), clasifica cada línea como normal o sospechosa y expone los resultados por API.

## Arquitectura

```
start_logging.sh ──(batch ~1KB cada N s)──> S3 input/
                                              │ Object Created (EventBridge)
                                              ▼
                              Step Functions: log-pipeline
                              ┌───────────────────────────────────────────┐
                              │ SplitBatch (Lambda split-batch)           │
                              │   descarga el batch y lo separa en líneas │
                              │ ClassifyLines (Map, una iteración x línea)│
                              │   IsSuspicious (Choice)                   │
                              │     ├─ sospechosa → SaveAlert  (Retry)    │──> DynamoDB SecurityAlerts
                              │     └─ normal     → SaveLog    (Retry)    │──> DynamoDB Logs
                              └───────────────────────────────────────────┘
                                                                         
HTTP API logging-system-api
  GET /alerts     → Lambda get-alerts → Scan de SecurityAlerts
  GET /logs?top=N → Lambda get-logs   → Query al GSI LastModifiedIndex de Logs
```

- Una línea es **sospechosa** si contiene `POSSIBLE BREAK-IN ATTEMPT` (severity `high`) o `Invalid user` (severity `medium`). Todo lo demás es normal.
- Las escrituras a DynamoDB (`SaveAlert`, `SaveLog`) tienen `Retry` con backoff exponencial para throttling.
- Todos los recursos usan el rol `LabRole` de AWS Academy.

## Tablas DynamoDB

| Tabla | Llave | Atributos |
|-------|-------|-----------|
| `SecurityAlerts` | PK `id` (S) | `id`, `timestamp`, `host`, `log`, `severity` |
| `Logs` | PK `id` (S) | `id`, `timestamp`, `host`, `log`, `gsi_pk` (siempre `"LOG"`), `last_modified` |

- GSI `LastModifiedIndex` en `Logs`: partition key `gsi_pk`, sort key `last_modified`.
- `last_modified` es el `LastModified` del batch en S3 (la hora real en que llegó, ISO 8601 UTC), no el timestamp que trae la línea. Así `/logs?top=N` hace `Query` con `Limit=N` y `ScanIndexForward=False` en lugar de `Scan`.
- `id` es `<key del batch>#<número de línea>`, por lo que reprocesar un batch no duplica registros.

## Estructura

```
script/
  config.sh           nombres y región compartidos
  deploy_all.sh       crea todo en orden
  create_tables.sh    tablas Logs y SecurityAlerts (+ GSI)
  create_pipeline.sh  bucket S3, Lambda split-batch, Step Functions, regla EventBridge
  create_api.sh       Lambdas get-alerts/get-logs y HTTP API
  start_logging.sh    envía batches de ~1KB a S3 cada N segundos
  teardown.sh         borra todos los recursos
  teardown_api.sh     borra solo el API y sus Lambdas
src/
  split_batch/        Lambda que descarga el batch y lo separa en líneas
  api/get_alerts/     Lambda de GET /alerts
  api/get_logs/       Lambda de GET /logs
statemachine/
  log_pipeline.asl.json  definición de la máquina de estados
```

`src/logging-system`, `create-s3-bucket.sh`, `package-lambda.sh`, `split-log.sh` y `send-log.sh` son de la versión anterior (Parte 2, tabla `LogEntries`) y no se usan en este flujo.

## Cómo correrlo

Desde AWS CloudShell (o una terminal con credenciales de AWS Academy), en `us-east-1`:

```bash
./script/deploy_all.sh
```

Crea tablas, bucket (`logging-system-<ACCOUNT_ID>`), Lambdas, máquina de estados, regla de EventBridge y API. Al final imprime la URL del API.

Enviar logs (un batch cada 30 segundos; descarga `OpenSSH_2k.log` de loghub si no está en `data/`):

```bash
./script/start_logging.sh 30
```

## API Gateway (consultas)

| Método | Ruta | Lambda | Descripción |
|--------|------|--------|-------------|
| GET | `/alerts` | `get-alerts` | Todas las alertas de `SecurityAlerts` (id, timestamp, host, log, severity), ordenadas por timestamp desc |
| GET | `/logs?top=N` | `get-logs` | Últimos N logs de `Logs` vía Query al GSI `LastModifiedIndex` (`ScanIndexForward=False`, `Limit=N`). `top` default 10, rango 1–1000; fuera de rango responde 400 |

```bash
API=https://<API_ID>.execute-api.us-east-1.amazonaws.com
curl -s "$API/alerts"
curl -s "$API/logs?top=5"
```

## Validar en consola

- **S3** → `logging-system-<ACCOUNT_ID>/input/`: aparece un archivo nuevo cada N segundos.
- **Step Functions** → `log-pipeline` → Executions → Graph view: el Map muestra cada línea yendo a `SaveLog` o `SaveAlert`.
- **DynamoDB** → `Logs` y `SecurityAlerts` → Explore table items: el conteo sube con cada batch.

## Eliminar recursos

```bash
./script/teardown.sh
```

Borra API Gateway, las Lambdas, la regla de EventBridge, la máquina de estados, las tablas (y `LogEntries` / `log-processor` de la versión anterior si existen) y vacía y borra el bucket.

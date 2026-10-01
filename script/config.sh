#!/bin/bash
# Configuracion compartida por los scripts del pipeline. Se usa con: source config.sh

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"

# El nombre del bucket es global en S3, por eso lleva el account id
BUCKET_NAME="${BUCKET_NAME:-logging-system-${ACCOUNT_ID}}"
INPUT_PREFIX="input/"

LOGS_TABLE="Logs"
ALERTS_TABLE="SecurityAlerts"
LOGS_INDEX="LastModifiedIndex"

SPLIT_FUNCTION="split-batch"
STATE_MACHINE_NAME="log-pipeline"
EVENT_RULE_NAME="log-batch-uploaded"

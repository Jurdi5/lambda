#!/bin/bash
# Simula el envio de logs: agrupa lineas del log de OpenSSH (loghub) en batches
# de ~1KB y sube uno a S3 cada N segundos.
#
# Uso: ./script/start_logging.sh [segundos] [archivo_log]
#   ./script/start_logging.sh 30
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

INTERVAL="${1:-30}"
LOG_FILE="${2:-$ROOT_DIR/data/OpenSSH_2k.log}"
MAX_BYTES="${MAX_BYTES:-1024}"
LOG_URL="https://raw.githubusercontent.com/logpai/loghub/master/OpenSSH/OpenSSH_2k.log"

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || (( INTERVAL < 1 )); then
  echo "Uso: $0 [segundos] [archivo_log]" >&2
  exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "Descargando log de ejemplo de loghub..."
  mkdir -p "$(dirname "$LOG_FILE")"
  curl -fsSL "$LOG_URL" -o "$LOG_FILE"
fi

BATCH_DIR="$BUILD_DIR/batches"
rm -rf "$BATCH_DIR"
mkdir -p "$BATCH_DIR"

# Junta lineas hasta ~MAX_BYTES por batch (una linea nunca se parte)
awk -v max="$MAX_BYTES" -v dir="$BATCH_DIR" '
  {
    line_size = length($0) + 1
    if (size > 0 && size + line_size > max) { close(file); n++; size = 0 }
    file = sprintf("%s/batch-%05d.log", dir, n)
    print > file
    size += line_size
  }
' "$LOG_FILE"

TOTAL="$(find "$BATCH_DIR" -name 'batch-*.log' | wc -l | tr -d ' ')"
echo "$TOTAL batches de ~${MAX_BYTES}B listos, enviando a s3://${BUCKET_NAME}/${INPUT_PREFIX} cada ${INTERVAL}s"
echo "Ctrl+C para detener"

count=0
for batch in "$BATCH_DIR"/batch-*.log; do
  count=$((count + 1))
  key="${INPUT_PREFIX}openssh-$(date -u +%Y%m%dT%H%M%SZ)-$(basename "$batch")"
  aws s3 cp "$batch" "s3://${BUCKET_NAME}/${key}" --only-show-errors
  echo "[$(date +%H:%M:%S)] ${count}/${TOTAL} $(wc -c < "$batch" | tr -d ' ')B -> ${key}"

  if (( count < TOTAL )); then
    sleep "$INTERVAL"
  fi
done

echo "Todos los batches enviados"

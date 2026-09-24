#!/bin/bash
# split-log.sh <archivo_log> <carpeta_salida>
INPUT_FILE=$1
OUT_DIR=${2:-batches}
MAX_BYTES=1024

mkdir -p "$OUT_DIR"

batch=""
batch_size=0
batch_num=0

while IFS= read -r line; do
  line_size=${#line}
  if (( batch_size + line_size > MAX_BYTES )) && (( batch_size > 0 )); then
    ts=$(date +%s%N)
    echo -n "$batch" > "$OUT_DIR/openssh-${ts}.log"
    batch=""
    batch_size=0
    ((batch_num++))
    sleep 0.001  # asegura timestamps distintos
  fi
  batch+="$line"$'\n'
  batch_size=$((batch_size + line_size + 1))
done < "$INPUT_FILE"

# último batch
if (( batch_size > 0 )); then
  ts=$(date +%s%N)
  echo -n "$batch" > "$OUT_DIR/openssh-${ts}.log"
  ((batch_num++))
fi

echo "Generados $batch_num batches en $OUT_DIR/"
#!/usr/bin/env bash
# Fine-tunes one JARVIS voice with Piper from the LJ Speech medium checkpoint (public-domain data), using our own
# phonemes (`--data.phoneme_type text`, see phonemes.py), then exports ONNX for the app.
#
#   bash train_voice.sh tr jarvis_tr_george 1000 [BATCH] [extra piper flags...]
#   bash train_voice.sh en jarvis_en_michael 1000 [BATCH]
#   bash train_voice.sh tr jarvis_tr_george export     # export the latest checkpoint only
#
# Speed: 6 data workers (Piper's default of 1 starves the GPU), validation every 25 epochs, bf16 mixed precision.
# Keep the UTMOS score on: Piper's checkpoint callback monitors `val_mos` and fails at the first validation without it
# (it only runs every 25 epochs, so its cost is small).
set -euo pipefail
LANG_CODE=$1; NAME=$2; EPOCHS=$3; BATCH=${4:-16}; EXTRA=("${@:5}")
ROOT=/root/voice
TOOLS=$(dirname "$(readlink -f "$0")")
RUN=$ROOT/runs/$NAME
OUT=$ROOT/out
mkdir -p "$RUN" "$OUT"
. $ROOT/.venv-piper/bin/activate
cd $ROOT/piper1-gpl

if [ "$EPOCHS" != "export" ]; then
  python -m piper.train fit \
    --data.voice_name "$NAME" \
    --data.csv_path "$ROOT/data_$LANG_CODE/metadata.csv" \
    --data.audio_dir "$ROOT/data_$LANG_CODE/wav" \
    --data.phoneme_type text \
    --data.espeak_voice "$([ "$LANG_CODE" = tr ] && echo tr || echo en-us)" \
    --data.cache_dir "$RUN/cache" \
    --data.config_path "$OUT/$NAME.onnx.json" \
    --data.batch_size "$BATCH" \
    --data.num_test_examples 5 \
    --data.num_workers 6 \
    --model.sample_rate 22050 \
    --model.warmstart_ckpt "$ROOT/base/en/en_US/ljspeech/medium/lj-med_1000.ckpt" \
    --trainer.max_epochs "$EPOCHS" \
    --trainer.check_val_every_n_epoch 25 \
    --trainer.precision bf16-mixed \
    --trainer.default_root_dir "$RUN" \
    "${EXTRA[@]}" \
    2>&1 | tee -a "$RUN/train.log"
fi

CKPT=$(ls -t "$RUN"/lightning_logs/version_*/checkpoints/*.ckpt | head -1)
echo "exporting $CKPT"
rm -f "$OUT/$NAME.onnx"
python "$TOOLS/export_onnx.py" --checkpoint "$CKPT" --output-file "$OUT/$NAME.onnx"
[ -s "$OUT/$NAME.onnx" ] || { echo "export failed: no $OUT/$NAME.onnx"; exit 3; }
ls -la "$OUT"

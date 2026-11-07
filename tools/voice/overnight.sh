#!/usr/bin/env bash
# Whole JARVIS voice pipeline in one unattended run (WSL, root):
#   TR data (resume) -> Whisper filter -> TR training -> EN training -> evaluation samples.
# Progress: /root/voice/overnight.log (stage lines start with "##").
#   bash overnight.sh [EPOCHS]
set -uo pipefail
EPOCHS=${1:-1000}
ROOT=/root/voice
TOOLS=/mnt/c/Users/niino/Desktop/SPOR/tools/voice
LOG=$ROOT/overnight.log
cd "$TOOLS"
stage() { echo "## $(date '+%F %T') $*" | tee -a "$LOG"; }

train() {  # lang name; batch 32 first, 16 if the GPU runs out of memory
  local lang=$1 name=$2
  for batch in 32 16; do
    if ls "$ROOT/runs/$name"/lightning_logs/version_*/checkpoints/*.ckpt > /dev/null 2>&1; then
      stage "train $name: keeping the failed run's checkpoints, not retrying (export: bash train_voice.sh $lang $name export)"
      return 1
    fi
    stage "train $name epochs=$EPOCHS batch=$batch"
    rm -rf "$ROOT/runs/$name"
    if bash train_voice.sh "$lang" "$name" "$EPOCHS" "$batch" --data.num_workers 4 >> "$LOG.$name" 2>&1; then
      stage "train $name done"; return 0
    fi
    stage "train $name failed with batch=$batch (see $LOG.$name)"
  done
  return 1
}

evaluate() {  # lang name
  local lang=$1 name=$2 out=$ROOT/eval/$1
  [ -f "$ROOT/out/$name.onnx" ] || { stage "eval $name skipped: no model"; return; }
  "$ROOT/.venv-piper/bin/python" eval_voice.py synth "$lang" "$ROOT/out/$name.onnx" "$out" "$ROOT/text/cmudict.dict" >> "$LOG" 2>&1
  "$ROOT/.venv-chatterbox/bin/python" eval_voice.py asr "$lang" "$out" 2>/dev/null | grep -E "CER" | tee -a "$LOG"
  stage "eval $name done -> $out"
}

stage "start"
if [ -f "$ROOT/data_tr/metadata.csv" ]; then
  stage "TR data already filtered ($(wc -l < "$ROOT/data_tr/metadata.csv") clips), skipping generation"
else
  stage "TR data generation (resume)"
  "$ROOT/.venv-chatterbox/bin/python" generate_dataset.py tr "$ROOT/text/sentences_tr.txt" "$ROOT/data_tr" \
    "$ROOT/samples/EN_bm_george.wav" > "$ROOT/gen_tr.log" 2>&1
  grep -E "^done" "$ROOT/gen_tr.log" | tee -a "$LOG"
  stage "TR filter"
  "$ROOT/.venv-chatterbox/bin/python" filter_dataset.py tr "$ROOT/data_tr" "$ROOT/text/cmudict.dict" 2>/dev/null | tail -1 | tee -a "$LOG"
fi

train tr jarvis_tr_george && evaluate tr jarvis_tr_george
train en jarvis_en_michael && evaluate en jarvis_en_michael
stage "finished"

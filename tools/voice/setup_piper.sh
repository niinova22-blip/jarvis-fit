#!/usr/bin/env bash
# Piper (VITS) training environment in WSL: /root/voice/.venv-piper with the CUDA 12.8 PyTorch the RTX 50
# series needs. Training code is GPL-3 and stays on this computer; only the trained weights (ours) ship.
# Base checkpoint: en_US ljspeech medium (public-domain data) — the only permissively licensed medium
# checkpoint; Turkish fine-tunes from it too (Piper docs: cross-language warm start works).
set -euo pipefail
export PATH="/root/.local/bin:$PATH"
cd /root/voice
[ -d piper1-gpl ] || git clone -q --depth 1 https://github.com/OHF-Voice/piper1-gpl.git
[ -d .venv-piper ] || uv venv --python 3.12 .venv-piper > /dev/null
. .venv-piper/bin/activate
uv pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
cd piper1-gpl
uv pip install -e '.[train]' 2>&1 | tail -1
# Keep the CUDA 12.8 build if the extras pulled another torch.
python -c "import torch,sys; sys.exit(0 if torch.version.cuda and torch.version.cuda.startswith('12.8') else 1)" \
  || uv pip install --reinstall torch torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
./build_monotonic_align.sh > /dev/null
python setup.py build_ext --inplace > /dev/null 2>&1 || true
mkdir -p /root/voice/base
# huggingface_hub lives in the teacher venv; the checkpoints repo is a dataset repo.
/root/voice/.venv-kokoro/bin/python - <<'PY'
from huggingface_hub import hf_hub_download
for f in ["en/en_US/ljspeech/medium/lj-med_1000.ckpt", "en/en_US/ljspeech/medium/config.json", "en/en_US/ljspeech/medium/MODEL_CARD"]:
    print(hf_hub_download("rhasspy/piper-checkpoints", f, repo_type="dataset", local_dir="/root/voice/base"))
PY
python -c "import torch, piper.train; print('piper train ok, torch', torch.__version__, torch.cuda.is_available())"

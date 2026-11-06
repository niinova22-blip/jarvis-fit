#!/usr/bin/env bash
# Training environment for JARVIS custom voices (run inside WSL2 Ubuntu as root).
# RTX 50-series (Blackwell, sm_120) needs PyTorch built for CUDA 12.8+.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq build-essential cmake ninja-build git ffmpeg sox libsndfile1 curl espeak-ng > /dev/null
if ! command -v uv > /dev/null && [ ! -x /root/.local/bin/uv ]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1
fi
export PATH="/root/.local/bin:$PATH"
mkdir -p /root/voice && cd /root/voice
[ -d .venv ] || uv venv --python 3.12 .venv > /dev/null
. .venv/bin/activate
uv pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
uv pip install numpy scipy soundfile librosa pyworld scikit-learn tqdm speechbrain 2>&1 | tail -1
python - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.cuda.is_available(), torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
x = torch.randn(2048, 2048, device="cuda")
print("matmul ok", bool((x @ x).abs().sum().item() > 0))
PY

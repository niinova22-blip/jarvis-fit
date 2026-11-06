#!/usr/bin/env bash
# Separate venvs for the "teacher" models used offline to design JARVIS's voice:
#  - Kokoro-82M (Apache-2.0) English voices
#  - Chatterbox Multilingual (MIT) for Turkish in the same voice
# Both reuse the CUDA 12.8 PyTorch needed by the RTX 50 series.
set -euo pipefail
export PATH="/root/.local/bin:$PATH"
cd /root/voice
for env in kokoro chatterbox; do
  [ -d ".venv-$env" ] || uv venv --python 3.12 ".venv-$env" > /dev/null
  . ".venv-$env/bin/activate"
  uv pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
  deactivate
done
. .venv-kokoro/bin/activate
uv pip install "kokoro>=0.9" soundfile "misaki[en]" 2>&1 | tail -1
python -c "import kokoro, torch; print('kokoro ok', torch.cuda.is_available())"
deactivate
. .venv-chatterbox/bin/activate
# chatterbox pins an older torch; keep our CUDA 12.8 build and install the rest of its deps.
uv pip install --no-deps "chatterbox-tts" 2>&1 | tail -1
uv pip install numpy librosa soundfile transformers diffusers conformer safetensors s3tokenizer resemble-perth \
  pykakasi spacy-pkuseg huggingface_hub omegaconf einops 2>&1 | tail -1
python -c "import chatterbox, torch; print('chatterbox ok', torch.cuda.is_available())"

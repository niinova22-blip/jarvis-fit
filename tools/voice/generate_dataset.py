"""Synthesises the training audio for one JARVIS voice from the teacher models (resumable).

    tr (venv .venv-chatterbox): python generate_dataset.py tr SENTENCES OUT_DIR REF_WAV [LIMIT]
    en (venv .venv-kokoro):     python generate_dataset.py en SENTENCES OUT_DIR VOICE   [LIMIT]

tr: Chatterbox Multilingual (MIT) speaking Turkish with the timbre of REF_WAV, a Kokoro (Apache-2.0) English
    sample (bm_george) — a synthetic voice, not a real person's.
en: Kokoro-82M voice (am_michael).
Output: OUT_DIR/wav/NNNNN.wav (22.05 kHz mono, trimmed, level-matched) and OUT_DIR/metadata_raw.csv (id|text).
"""
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torchaudio

lang, sentences_path, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
ref = sys.argv[4]
limit = int(sys.argv[5]) if len(sys.argv) > 5 else None
SR = 22050
(out / "wav").mkdir(parents=True, exist_ok=True)
lines = [l.strip() for l in sentences_path.read_text(encoding="utf-8").splitlines() if l.strip()][:limit]


def trim(audio: np.ndarray, top_db: float = 40, frame: int = 512) -> np.ndarray:
    """Cuts leading/trailing frames quieter than top_db below the loudest frame."""
    n = len(audio) // frame
    if n == 0:
        return audio
    energy = np.sqrt(np.mean(audio[: n * frame].reshape(n, frame) ** 2, axis=1)) + 1e-9
    db = 20 * np.log10(energy / energy.max())
    loud = np.where(db > -top_db)[0]
    return audio[loud[0] * frame: (loud[-1] + 1) * frame] if len(loud) else audio


def finish(audio: np.ndarray, sr: int) -> np.ndarray:
    tensor = torch.from_numpy(np.asarray(audio, dtype=np.float32))
    audio = torchaudio.functional.resample(tensor, sr, SR).numpy()
    audio = trim(audio)
    rms = float(np.sqrt(np.mean(audio ** 2)) + 1e-9)
    audio = audio * (10 ** (-20 / 20) / rms)  # -20 dBFS RMS
    peak = float(np.max(np.abs(audio)))
    if peak > 0.97:
        audio *= 0.97 / peak
    pad = np.zeros(int(0.08 * SR), dtype=np.float32)
    return np.concatenate([pad, audio, pad])


if lang == "tr":
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
    model = ChatterboxMultilingualTTS.from_pretrained(device="cuda")

    def synth(text: str) -> np.ndarray:
        torch.manual_seed(7)
        wav = model.generate(text, language_id="tr", audio_prompt_path=ref, exaggeration=0.5, cfg_weight=0.0)
        return finish(wav.squeeze(0).cpu().numpy(), model.sr)
else:
    from kokoro import KPipeline
    pipe = KPipeline(lang_code=ref[0], repo_id="hexgrad/Kokoro-82M")

    def synth(text: str) -> np.ndarray:
        audio = np.concatenate([np.asarray(chunk) for _, _, chunk in pipe(text, voice=ref, speed=1.0)])
        return finish(audio, 24000)

meta = []
start, done = time.time(), 0
for i, text in enumerate(lines):
    uid = f"{i:05d}"
    meta.append(f"{uid}|{text}")
    path = out / "wav" / f"{uid}.wav"
    if path.exists():
        continue
    try:
        audio = synth(text)
    except Exception as error:  # the teacher occasionally fails on very short inputs; skip those
        print("skip", uid, text[:40], type(error).__name__, flush=True)
        continue
    sf.write(path, audio, SR)
    done += 1
    if done % 25 == 0:
        rate = (time.time() - start) / done
        print(f"{i + 1}/{len(lines)}  {rate:.1f} s/sentence  ~{rate * (len(lines) - i - 1) / 60:.0f} min left", flush=True)
(out / "metadata_raw.csv").write_text("\n".join(meta) + "\n", encoding="utf-8")
print("done", len(lines), "sentences,", done, "new")

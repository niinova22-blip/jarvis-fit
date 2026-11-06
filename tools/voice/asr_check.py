"""Intelligibility check: transcribe generated Turkish samples with Whisper and report character error rate."""
import re
import sys
from pathlib import Path

import librosa
import torch
from transformers import pipeline

TR = ("Günaydın Mert. Bugün saat yedide bacak antrenmanın var, günlük protein hedefin yüz kırk gram. "
      "Hadi başlıyoruz! Üç tekrar kaldı. Sırtını dik tut. Harika bir set. Şimdi altmış saniye dinlen.")


ONES = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
TENS = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]


def tr_words(n: int) -> str:
    """Turkish number words (same rules as SpeechText.spell in the app)."""
    if n == 0:
        return "sıfır"
    words = []
    for scale, name in ((1_000_000, "milyon"), (1000, "bin")):
        if n >= scale:
            count, n = divmod(n, scale)
            if not (scale == 1000 and count == 1):
                words.append(tr_words(count))
            words.append(name)
    hundreds, rest = divmod(n, 100)
    if hundreds:
        words += ([ONES[hundreds]] if hundreds > 1 else []) + ["yüz"]
    words += [w for w in (TENS[rest // 10], ONES[rest % 10]) if w]
    return " ".join(words)


def normalize(text: str) -> str:
    # Whisper writes numbers as digits ("7'de", "140"); spell them so only real mistakes count.
    text = re.sub(r"(\d+)['’]?", lambda m: tr_words(int(m.group(1))), text)
    text = text.replace("I", "ı").replace("İ", "i").lower()
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())


def cer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    d = list(range(len(h) + 1))
    for i, rc in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hc in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rc != hc))
    return d[len(h)] / max(1, len(r))


asr = pipeline("automatic-speech-recognition", model="openai/whisper-large-v3-turbo", device=0, torch_dtype=torch.float16)
for wav in sorted(Path(sys.argv[1]).glob("TR_*.wav")):
    audio, _ = librosa.load(wav, sr=16000)
    text = asr(audio, generate_kwargs={"language": "turkish"})["text"].strip()
    print(f"{wav.stem:16s} CER {cer(TR, text):.1%} | {text}")

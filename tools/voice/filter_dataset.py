"""Keeps only training clips the teacher spoke correctly, and writes Piper's training CSV.

    python filter_dataset.py LANG DATA_DIR CMUDICT [MAX_CER]      (venv .venv-chatterbox: has Whisper)

Each clip is transcribed with Whisper large-v3-turbo; clips whose character error rate (numbers spelled out,
punctuation ignored) exceeds MAX_CER (default 0.08), or that are shorter than 0.4 s / longer than 15 s, are
dropped. Output: DATA_DIR/metadata.csv as `NNNNN.wav|phonemes` for `--data.phoneme_type text`, plus
DATA_DIR/rejected.tsv for inspection.
"""
import re
import sys
from pathlib import Path

import soundfile as sf
import torch
from transformers import pipeline

sys.path.insert(0, str(Path(__file__).parent))
import phonemes  # noqa: E402
from numwords import en_words, tr_words  # noqa: E402

lang, data = sys.argv[1], Path(sys.argv[2])
lexicon = phonemes.load_cmudict(sys.argv[3]) if lang == "en" else {}
max_cer = float(sys.argv[4]) if len(sys.argv) > 4 else 0.08


def normalize(text: str) -> str:
    if lang == "tr":
        text = re.sub(r"(\d+)['’]?", lambda m: " " + tr_words(int(m.group(1))) + " ", text)
        text = text.replace("I", "ı").replace("İ", "i").lower()
    else:
        text = re.sub(r"(\d),(\d{3})", r"\1\2", text)
        text = re.sub(r"(\d+)(st|nd|rd|th)?",lambda m: " " + en_words(int(m.group(1))) + " ", text)
        text = re.sub(r"\b([ap])\.?\s?m\b\.?", r"\1 m", text.lower())
        text = text.replace("-", " ")
    return " ".join("".join(c if c.isalnum() or c == "'" else " " for c in text).split())


def cer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    d = list(range(len(h) + 1))
    for i, rc in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hc in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rc != hc))
    return d[len(h)] / max(1, len(r))


rows = []
for line in (data / "metadata_raw.csv").read_text(encoding="utf-8").splitlines():
    uid, text = line.split("|", 1)
    wav = data / "wav" / f"{uid}.wav"
    if wav.exists():
        rows.append((uid, text, wav))

asr = pipeline("automatic-speech-recognition", model="openai/whisper-large-v3-turbo", device=0, torch_dtype=torch.float16)
language = "turkish" if lang == "tr" else "english"
kept, rejected, total_seconds = [], [], 0.0
batch = 16
for start in range(0, len(rows), batch):
    chunk = rows[start:start + batch]
    audios = []
    for _, _, wav in chunk:
        audio, sr = sf.read(wav, dtype="float32")
        audios.append({"raw": audio, "sampling_rate": sr})
    results = asr(audios, batch_size=batch, generate_kwargs={"language": language})
    for (uid, text, wav), result in zip(chunk, results):
        seconds = sf.info(wav).duration
        heard = result["text"].strip()
        error = cer(text, heard)
        if not 0.4 <= seconds <= 15 or error > max_cer:
            rejected.append(f"{uid}\t{error:.3f}\t{seconds:.1f}\t{text}\t{heard}")
            continue
        ph = phonemes.turkish(text) if lang == "tr" else phonemes.english(text, lexicon)
        kept.append(f"{uid}.wav|{ph}")
        total_seconds += seconds
    print(f"{min(start + batch, len(rows))}/{len(rows)} kept {len(kept)}", flush=True)

(data / "metadata.csv").write_text("\n".join(kept) + "\n", encoding="utf-8")
(data / "rejected.tsv").write_text("\n".join(rejected) + "\n", encoding="utf-8")
print(f"kept {len(kept)}/{len(rows)} clips, {total_seconds / 3600:.2f} h audio, "
      f"mean {total_seconds / max(1, len(kept)):.1f} s; rejected {len(rejected)}")

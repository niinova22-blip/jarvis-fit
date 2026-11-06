"""Quick look at the ISSAI TSC corpus: sample rate, durations, example transcripts."""
import random
import sys
from pathlib import Path

import soundfile as sf

root = Path(sys.argv[1] if len(sys.argv) > 1 else "/root/voice/data/ISSAI_TSC_218/Train")
wavs = sorted(root.glob("*.wav"))
random.seed(0)
sample = random.sample(wavs, 2000)
rates, durations = {}, []
for w in sample:
    info = sf.info(w)
    rates[info.samplerate] = rates.get(info.samplerate, 0) + 1
    durations.append(info.duration)
durations.sort()
print("files", len(wavs))
print("sample rates (2000 sampled)", rates)
print("duration p10/p50/p90/max", [round(durations[int(len(durations) * q)], 2) for q in (0.1, 0.5, 0.9)], round(durations[-1], 2))
print("estimated total hours", round(sum(durations) / len(durations) * len(wavs) / 3600, 1))
for w in sample[:12]:
    print(w.stem, "|", w.with_suffix(".txt").read_text(encoding="utf-8").strip()[:120])
# Are consecutive ids from the same recording session? Print a run of neighbours.
ids = sorted(int(w.stem) for w in wavs)
start = ids[len(ids) // 2]
for i in range(start, start + 8):
    p = root / f"{i}.txt"
    if p.exists():
        print("seq", i, round(sf.info(root / f"{i}.wav").duration, 2), p.read_text(encoding="utf-8").strip()[:90])

"""Listens to a trained JARVIS voice the way the app runs it (our phonemizer + Piper ids + ONNX).

    synth (venv .venv-piper):      python eval_voice.py synth LANG MODEL.onnx OUT_DIR [CMUDICT]
    asr   (venv .venv-chatterbox): python eval_voice.py asr LANG OUT_DIR

synth writes OUT_DIR/NN.wav plus OUT_DIR/texts.txt; asr transcribes them with Whisper and prints the character
error rate per sentence (numbers spelled out, punctuation ignored) and the mean.
"""
import json
import re
import sys
import time
import unicodedata
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
import phonemes  # noqa: E402
from numwords import en_words, tr_words  # noqa: E402

TESTS = {
    "tr": ["Günaydın Mert. Bugün saat yedide bacak antrenmanın var.",
           "Günlük protein hedefin yüz kırk gram.",
           "Hadi başlıyoruz! Üç tekrar kaldı.",
           "Sırtını dik tut, dizlerin ayak uçlarını geçmesin.",
           "Harika bir set. Şimdi altmış saniye dinlen.",
           "Sıradaki hareket: skuat. Üç set on iki tekrar yapacağız.",
           "Merhaba, ben Carvis. Hazır olduğunda başlayalım.",
           "Bu hafta dört antrenman tamamladın, geçen haftadan bir fazla."],
    "en": ["Good morning, Alex. Today we're training legs at seven p.m.",
           "Your daily protein target is one hundred forty grams.",
           "Let's go! Three more reps.",
           "Keep your back straight and don't let your knees cave in.",
           "Great set. Rest for sixty seconds.",
           "Next exercise: squat. We'll do three sets of twelve.",
           "Hi, I'm Jarvis. Let's start when you're ready.",
           "You finished four workouts this week, one more than last week."],
}
stage, lang = sys.argv[1], sys.argv[2]


def synth(model_path: str, out: Path, cmudict: str = "") -> None:
    import onnxruntime as ort
    config = json.loads(Path(model_path + ".json").read_text(encoding="utf-8"))
    id_map = {k: v[0] for k, v in config["phoneme_id_map"].items()}
    inference = config.get("inference", {})
    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    lexicon = phonemes.load_cmudict(cmudict) if lang == "en" else {}
    out.mkdir(parents=True, exist_ok=True)
    (out / "texts.txt").write_text("\n".join(TESTS[lang]) + "\n", encoding="utf-8")
    total_audio = total_time = 0.0
    for i, text in enumerate(TESTS[lang]):
        ph = phonemes.turkish(text) if lang == "tr" else phonemes.english(text, lexicon)
        ids = [id_map["^"], id_map["_"]]
        for symbol in unicodedata.normalize("NFD", ph):
            if symbol in id_map:
                ids += [id_map[symbol], id_map["_"]]
        ids.append(id_map["$"])
        scales = np.array([inference.get("noise_scale", 0.667), inference.get("length_scale", 1.0),
                           inference.get("noise_w", 0.8)], dtype=np.float32)
        start = time.time()
        audio = session.run(None, {"input": np.array([ids], dtype=np.int64),
                                   "input_lengths": np.array([len(ids)], dtype=np.int64), "scales": scales})[0].squeeze()
        total_time += time.time() - start
        total_audio += len(audio) / config["audio"]["sample_rate"]
        sf.write(out / f"{i:02d}.wav", np.clip(audio, -1, 1), config["audio"]["sample_rate"])
    print(f"synthesised {total_audio:.1f} s of audio in {total_time:.1f} s (CPU, real-time factor {total_time / total_audio:.2f})")


def normalize(text: str) -> str:
    if lang == "tr":
        text = re.sub(r"(\d+)['’]?", lambda m: " " + tr_words(int(m.group(1))) + " ", text)
        text = text.replace("I", "ı").replace("İ", "i").lower()
    else:
        text = re.sub(r"(\d),(\d{3})", r"\1\2", text)
        text = re.sub(r"(\d+)(st|nd|rd|th)?", lambda m: " " + en_words(int(m.group(1))) + " ", text)
        text = re.sub(r"\b([ap])\.?\s?m\b\.?", r"\1 m", text.lower())
    return " ".join("".join(c if c.isalnum() or c == "'" else " " for c in text).split())


def cer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    d = list(range(len(h) + 1))
    for i, rc in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hc in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rc != hc))
    return d[len(h)] / max(1, len(r))


def asr(out: Path) -> None:
    import torch
    from transformers import pipeline
    model = pipeline("automatic-speech-recognition", model="openai/whisper-large-v3-turbo", device=0, torch_dtype=torch.float16)
    texts = (out / "texts.txt").read_text(encoding="utf-8").splitlines()
    errors = []
    for i, text in enumerate(texts):
        audio, sr = sf.read(out / f"{i:02d}.wav", dtype="float32")
        heard = model({"raw": audio, "sampling_rate": sr}, generate_kwargs={"language": "turkish" if lang == "tr" else "english"})["text"].strip()
        errors.append(cer(text, heard))
        print(f"{i:02d} CER {errors[-1]:.1%} | {heard}")
    print(f"mean CER {sum(errors) / len(errors):.1%}")


if stage == "synth":
    synth(sys.argv[3], Path(sys.argv[4]), sys.argv[5] if len(sys.argv) > 5 else "")
else:
    asr(Path(sys.argv[3]))

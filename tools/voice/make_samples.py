"""Generates listening samples for choosing JARVIS's male voice.

Stage 1 (venv .venv-kokoro):     python make_samples.py en  OUT_DIR
Stage 2 (venv .venv-chatterbox): python make_samples.py tr  OUT_DIR
English comes from Kokoro-82M (Apache-2.0). Turkish is Chatterbox Multilingual (MIT) speaking in
the same voice, using the Kokoro English sample as the voice reference (no real person's voice).
"""
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

VOICES = ["am_michael", "am_fenrir", "am_puck", "am_onyx", "bm_george", "bm_fable"]
EN = ("Good morning, Alex. Today we're training legs at seven p.m., and your protein target is one hundred "
      "forty grams. Let's go! Three more reps. Keep your back straight. Great set. Rest for sixty seconds.")
TR = ("Günaydın Mert. Bugün saat yedide bacak antrenmanın var, günlük protein hedefin yüz kırk gram. "
      "Hadi başlıyoruz! Üç tekrar kaldı. Sırtını dik tut. Harika bir set. Şimdi altmış saniye dinlen.")

stage, out = sys.argv[1], Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

if stage == "en":
    from kokoro import KPipeline
    pipes = {}
    for voice in VOICES:
        lang = voice[0]  # 'a' American, 'b' British
        pipe = pipes.setdefault(lang, KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M"))
        audio = np.concatenate([np.asarray(chunk) for _, _, chunk in pipe(EN, voice=voice, speed=1.0)])
        sf.write(out / f"EN_{voice}.wav", audio, 24000)
        print("en", voice, round(len(audio) / 24000, 1), "s")
else:
    import torch
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
    model = ChatterboxMultilingualTTS.from_pretrained(device="cuda")
    for voice in VOICES:
        ref = out / f"EN_{voice}.wav"
        torch.manual_seed(7)
        # cfg_weight 0 reduces carrying the English accent into Turkish (cross-language reference).
        wav = model.generate(TR, language_id="tr", audio_prompt_path=str(ref), exaggeration=0.5, cfg_weight=0.0)
        sf.write(out / f"TR_{voice}.wav", wav.squeeze(0).cpu().numpy(), model.sr)
        print("tr", voice, round(wav.shape[-1] / model.sr, 1), "s")

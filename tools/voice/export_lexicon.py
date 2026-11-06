"""Exports the app-side files shared with phonemes.py.

    python export_lexicon.py CMUDICT SENTENCES_TR SENTENCES_EN REPO_DIR

1. JarvisFit/Resources/Voices/en_lexicon.tsv  — CMUdict (BSD-style licence) as `word<TAB>ipa`, first pronunciation,
   only words the phonemizer can look up ([a-z']).
2. Packages/JarvisCore/Tests/JarvisCoreTests/Fixtures/phonemes_golden.tsv — `lang<TAB>text<TAB>phonemes` produced by
   phonemes.py; the Swift Phonemizer must reproduce every line.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import phonemes  # noqa: E402

cmudict, sent_tr, sent_en, repo = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
lexicon = phonemes.load_cmudict(cmudict)

voices = repo / "JarvisFit/Resources/Voices"
voices.mkdir(parents=True, exist_ok=True)
rows = [f"{w}\t{phonemes.arpa_to_ipa(p)}" for w, p in sorted(lexicon.items()) if re.fullmatch(r"[a-z']+", w)]
(voices / "en_lexicon.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")
print("lexicon words", len(rows))

extra_tr = ["Saat on dokuzda bacak antrenmanın var.", "Ağır değil, dağ gibi; eğer öğlen gelirsen.", "Skuat'lar ve lanç.",
            "İyi, ılık, IŞIK, İSTANBUL.", "Kâğıt, hâlâ, rüzgâr.", "Carvis: hazır mısın?", "Bir-iki-üç — başla!",
            "Mert'in protein hedefi yüz kırk gram.", "Yarım kilo; bir virgül altı."]
extra_en = ["Your workout is at seven p.m. today.", "Hi, I'm Jarvis's coach.", "Squats, lunges and burpees!",
            "The xylophonist Zbigniew qualified.", "It's twelve fifteen a.m.; don't stop.", "Plank: thirty seconds."]
golden = []
for lang, path, extra in (("tr", sent_tr, extra_tr), ("en", sent_en, extra_en)):
    lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    for text in lines[:600] + extra:
        ph = phonemes.turkish(text) if lang == "tr" else phonemes.english(text, lexicon)
        golden.append(f"{lang}\t{text}\t{ph}")
fixture = repo / "Packages/JarvisCore/Tests/JarvisCoreTests/Fixtures/phonemes_golden.tsv"
fixture.write_text("\n".join(golden) + "\n", encoding="utf-8")
print("golden lines", len(golden))

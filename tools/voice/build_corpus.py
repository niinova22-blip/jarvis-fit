"""Builds the sentence lists for JARVIS's voices.

    python build_corpus.py REPO_DIR TEXT_DIR OUT_DIR [N_GENERAL]

Sources (all licence-clean):
  - Mozilla Common Voice sentence collector (CC0): general sentences, chosen greedily for phoneme-pair coverage
  - the app's own Turkish/English strings (JarvisCore + app) without interpolation
  - coach templates with numbers written as words (what SpeechText produces at run time)
Writes OUT_DIR/sentences_tr.txt and sentences_en.txt (one sentence per line, already speech-ready).
"""
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import phonemes  # noqa: E402
from numwords import en_words, tr_words  # noqa: E402

repo, text_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
n_general = int(sys.argv[4]) if len(sys.argv) > 4 else 1150
random.seed(7)

# Same respellings as SpeechText.turkishLexicon (Swift).
TR_LEXICON = [
    ("jarvis fit", "Carvis Fit"), ("jarvis", "Carvis"), ("push-up", "puşap"), ("push up", "puşap"), ("pushup", "puşap"),
    ("jumping jack", "camping cek"), ("biceps curl", "bayseps körl"), ("biceps", "bayseps"), ("glute bridge", "glut briç"),
    ("shoulder press", "şoldır pres"), ("lateral raise", "laterıl reyz"), ("squat", "skuat"), ("lunge", "lanç"),
    ("plank", "plenk"), ("press", "pres"), ("crunch", "kranç"), ("deadlift", "dedlift"), ("burpee", "börpi"),
    ("cardio", "kardiyo"), ("fit check", "fit çek"), ("iphone", "ayfon"),
]


def tr_respell(text: str) -> str:
    for word, spoken in TR_LEXICON:
        def repl(m, spoken=spoken):
            return spoken[0].upper() + spoken[1:] if m.group(0)[0].isupper() else spoken
        text = re.sub(r"(?i)\b" + re.escape(word), repl, text)
    return text


TR_ORD = ["", "birinci", "ikinci", "üçüncü", "dördüncü", "beşinci", "altıncı"]
EN_ORD = ["", "first", "second", "third", "fourth", "fifth", "sixth"]
EXERCISES_TR = ["skuat", "şınav", "lanç", "camping cek", "plenk", "bayseps körl", "omuz pres", "yana açış", "glut briç", "mekik"]
EXERCISES_EN = ["squat", "push-up", "lunge", "jumping jack", "plank", "biceps curl", "shoulder press", "lateral raise",
                "glute bridge", "crunch"]


def cap(s: str) -> str:
    first = {"i": "İ", "ı": "I"}.get(s[0], s[0].upper())
    return first + s[1:]


def templates_tr():
    lines = [cap(tr_words(n)) + "." for n in range(1, 31)]
    lines += [f"{cap(tr_words(n))} tekrar kaldı." for n in range(1, 13)]
    lines += [f"Son {tr_words(n)} tekrar, hadi!" for n in (2, 3, 4, 5)]
    lines += [f"{cap(o)} set başlıyor." for o in TR_ORD[1:]]
    lines += [f"{cap(tr_words(n))} saniye dinlen." for n in (20, 30, 45, 60, 75, 90, 120)]
    lines += [f"{cap(tr_words(n))} saniye kaldı." for n in (5, 10, 15, 30)]
    lines += [f"Günlük protein hedefin {tr_words(n)} gram." for n in (90, 110, 125, 140, 160, 180)]
    lines += [f"Bugün yaklaşık {tr_words(n)} kalori aldın." for n in (1250, 1800, 2100, 2450)]
    lines += [f"Sıradaki hareket: {e}." for e in EXERCISES_TR]
    lines += [f"{cap(tr_words(s))} set {tr_words(r)} tekrar {e} yapacağız." for s, r, e in
              [(3, 12, "skuat"), (4, 10, "şınav"), (3, 15, "lanç"), (3, 8, "omuz pres"), (2, 20, "mekik")]]
    lines += [f"Bugün saat {tr_words(h)}{suf} antrenmanın var." for h, suf in ((7, "de"), (18, "de"), (19, "da"), (20, "de"))]
    lines += [f"Kilon artı bir virgül {tr_words(n)} kilo değişti." for n in (2, 4)] + ["Kilon eksi yarım kilo değişti."]
    lines += ["Merhaba, ben Carvis. Hazır olduğunda başlayalım.", "Sırtını dik tut.", "Dizlerin ayak uçlarını geçmesin.",
              "Kalçanı biraz daha aşağı indir.", "Harika bir set!", "Nefesini tut, şimdi bırak.", "Tamam, not aldım.",
              "Biraz daha yavaş in.", "Telefonu biraz geriye al, tüm vücudun görünsün.", "Bugünlük bu kadar, harika iş çıkardın!"]
    return lines


def templates_en():
    lines = [cap(en_words(n)) + "." for n in range(1, 31)]
    lines += [f"{cap(en_words(n))} reps left." for n in range(2, 13)] + ["One rep left."]
    lines += [f"Last {en_words(n)} reps, come on!" for n in (2, 3, 4, 5)]
    lines += [f"{cap(o)} set, let's go." for o in EN_ORD[1:]]
    lines += [f"Rest for {en_words(n)} seconds." for n in (20, 30, 45, 60, 75, 90)]
    lines += [f"{cap(en_words(n))} seconds left." for n in (5, 10, 15, 30)]
    lines += [f"Your daily protein target is {en_words(n)} grams." for n in (90, 110, 125, 140, 160, 180)]
    lines += [f"You've had about {en_words(n)} calories today." for n in (1250, 1800, 2100, 2450)]
    lines += [f"Next exercise: {e}." for e in EXERCISES_EN]
    lines += [f"We'll do {en_words(s)} sets of {en_words(r)} {e}s." for s, r, e in
              [(3, 12, "squat"), (4, 10, "push-up"), (3, 15, "lunge"), (2, 20, "crunch")]]
    lines += [f"Your workout is at {en_words(h)} p.m. today." for h in (6, 7, 8)]
    lines += ["Hi, I'm Jarvis. Let's start when you're ready.", "Keep your back straight.", "Don't let your knees cave in.",
              "Go a little lower.", "Great set!", "Breathe in, now breathe out.", "Got it.", "Slow down on the way down.",
              "Move the phone back so I can see your whole body.", "That's it for today, great work!"]
    return lines


def app_strings():
    """(tr, en) literal pairs from the Swift sources, without interpolation."""
    pairs = []
    pattern = re.compile(r'(?:tr:\s*|t\(\s*)"((?:[^"\\]|\\.)*)",\s*(?:en:\s*)?"((?:[^"\\]|\\.)*)"')
    for path in list((repo / "Packages/JarvisCore/Sources").rglob("*.swift")) + list((repo / "JarvisFit").rglob("*.swift")):
        for tr, en in pattern.findall(path.read_text(encoding="utf-8")):
            if "\\" in tr or "\\" in en or re.search(r"\d|%|@", tr + en):
                continue
            if len(tr.split()) >= 3 and tr.rstrip()[-1:] in ".!?" and en.rstrip()[-1:] in ".!?":
                pairs.append((tr, en))
    return sorted(set(pairs))


TR_OK = re.compile(r"^[A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû ,.?!;:'’-]+$")
EN_OK = re.compile(r"^[A-Za-z ,.?!;:'-]+$")


def common_voice(path: Path, ok, lang, lexicon=None):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip().strip('"').strip()
        if not (30 <= len(line) <= 130) or not ok.match(line) or line[-1] not in ".?!":
            continue
        words = re.findall(r"[^\W\d_]+(?:'[^\W\d_]+)?", line)
        if not 5 <= len(words) <= 18 or any(len(w) > 1 and w.isupper() for w in words):
            continue
        if lang == "tr" and re.search(r"[qwxQWX]", line):
            continue
        if lang == "en" and any(w.lower() not in lexicon for w in words):
            continue
        out.append(line)
    return sorted(set(out))


def pick_by_coverage(candidates, count, to_phonemes):
    """Greedy: repeatedly take the sentence adding the most unseen phoneme pairs (random tie-break)."""
    random.shuffle(candidates)
    pool = [(s, {a + b for a, b in zip(to_phonemes(s), to_phonemes(s)[1:])}) for s in candidates[:20000]]
    seen, chosen = set(), []
    while pool and len(chosen) < count:
        best = max(range(len(pool)), key=lambda i: len(pool[i][1] - seen))
        if not pool[best][1] - seen:  # coverage saturated: fill randomly
            chosen += [s for s, _ in pool[: count - len(chosen)]]
            break
        s, pairs = pool.pop(best)
        seen |= pairs
        chosen.append(s)
    return chosen, len(seen)


lexicon = phonemes.load_cmudict(str(text_dir / "cmudict.dict"))
pairs = app_strings()
for lang in ("tr", "en"):
    if lang == "tr":
        general = common_voice(text_dir / "cv_tr.txt", TR_OK, "tr")
        # Skip app strings that still contain English-looking words (camelCase, q/w/x) after respelling.
        domain = templates_tr() + [s for s in (tr_respell(tr) for tr, _ in pairs)
                                   if not re.search(r"[qwxQWX]|[a-zçğıöşü][A-ZÇĞİÖŞÜ]", s)]
        to_ph = phonemes.turkish
    else:
        general = common_voice(text_dir / "cv_en.txt", EN_OK, "en", lexicon)
        domain = templates_en() + [en for _, en in pairs if all(w.lower() in lexicon for w in re.findall(r"[A-Za-z']+", en))]
        to_ph = lambda s: phonemes.english(s, lexicon)  # noqa: E731
    domain = list(dict.fromkeys(d for d in domain if len(d) <= 160))
    chosen, coverage = pick_by_coverage(general, n_general, to_ph)
    lines = domain + chosen
    (out_dir / f"sentences_{lang}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(lang, "candidates", len(general), "domain", len(domain), "general", len(chosen), "phoneme pairs", coverage)

"""JARVIS voice phonemizer (training side). The Swift port is JarvisCore/Voice/Phonemizer.swift; both must give
identical output (checked by a golden-file test). No espeak-ng (GPL) anywhere.

Turkish: spelling is close to phonemic, so it is a letter -> IPA map (+ soft g rules).
English: CMU Pronouncing Dictionary (BSD-style licence) ARPAbet -> IPA, letter rules for unknown words.
Output symbols all exist in Piper's standard phoneme_id_map, so a stock checkpoint can be fine-tuned.

    python phonemes.py tr "Günaydın Mert."
    python phonemes.py en "Good morning." /path/to/cmudict.dict
"""
import re
import sys
import unicodedata

PUNCT = set(",.?!;:")

# ---------------------------------------------------------------- Turkish
TR_MAP = {
    "a": "a", "â": "a", "b": "b", "c": "dʒ", "ç": "tʃ", "d": "d", "e": "e", "f": "f", "g": "ɡ", "h": "h",
    "ı": "ɯ", "i": "i", "î": "i", "j": "ʒ", "k": "k", "l": "l", "m": "m", "n": "n", "o": "o", "ö": "œ",
    "p": "p", "r": "ɾ", "s": "s", "ş": "ʃ", "t": "t", "u": "u", "û": "u", "ü": "y", "v": "v", "y": "j",
    "z": "z", "q": "k", "w": "v", "x": "ks",
}
TR_VOWELS = set("aâeıiîoöuûü")


def tr_lower(text: str) -> str:
    return text.replace("I", "ı").replace("İ", "i").lower()


def turkish(text: str) -> str:
    text = unicodedata.normalize("NFC", tr_lower(text))
    text = re.sub(r"(\w)['’](\w)", r"\1\2", text)
    out = []
    for i, ch in enumerate(text):
        if ch == "ğ":
            nxt = text[i + 1] if i + 1 < len(text) else ""
            prev = text[i - 1] if i > 0 else ""
            # Between vowels it is silent; after a vowel before a consonant/end it lengthens the vowel.
            if prev in TR_VOWELS and nxt not in TR_VOWELS:
                out.append("ː")
        elif ch in TR_MAP:
            out.append(TR_MAP[ch])
        elif ch in PUNCT:
            out.append(ch)
        elif ch.isspace() or ch in "-–—":
            out.append(" ")
    return tidy("".join(out))


# ---------------------------------------------------------------- English
ARPA = {
    "AA": "ɑː", "AE": "æ", "AH": "ʌ", "AO": "ɔː", "AW": "aʊ", "AY": "aɪ", "B": "b", "CH": "tʃ", "D": "d",
    "DH": "ð", "EH": "ɛ", "ER": "ɜː", "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "iː",
    "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ", "OW": "oʊ", "OY": "ɔɪ", "P": "p",
    "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "UH": "ʊ", "UW": "uː", "V": "v", "W": "w",
    "Y": "j", "Z": "z", "ZH": "ʒ",
}
# Unstressed variants.
ARPA0 = {"AH": "ə", "ER": "ɚ"}
LETTER_NAMES = {
    "a": "eɪ", "b": "biː", "c": "siː", "d": "diː", "e": "iː", "f": "ɛf", "g": "dʒiː", "h": "eɪtʃ", "i": "aɪ",
    "j": "dʒeɪ", "k": "keɪ", "l": "ɛl", "m": "ɛm", "n": "ɛn", "o": "oʊ", "p": "piː", "q": "kjuː", "r": "ɑːɹ",
    "s": "ɛs", "t": "tiː", "u": "juː", "v": "viː", "w": "dʌbəljuː", "x": "ɛks", "y": "waɪ", "z": "ziː",
}
# Rough letter rules for words missing from the dictionary (names, brands); longest match first.
EN_RULES = [
    ("tion", "ʃən"), ("sion", "ʒən"), ("ough", "oʊ"), ("igh", "aɪ"), ("tch", "tʃ"), ("sch", "sk"),
    ("ch", "tʃ"), ("sh", "ʃ"), ("th", "θ"), ("ph", "f"), ("wh", "w"), ("ck", "k"), ("ng", "ŋ"), ("qu", "kw"),
    ("ee", "iː"), ("ea", "iː"), ("oo", "uː"), ("ou", "aʊ"), ("ow", "aʊ"), ("oi", "ɔɪ"), ("oy", "ɔɪ"),
    ("ai", "eɪ"), ("ay", "eɪ"), ("au", "ɔː"), ("aw", "ɔː"), ("er", "ɚ"), ("ir", "ɜː"), ("ur", "ɜː"),
    ("ar", "ɑːɹ"), ("or", "ɔːɹ"),
    ("a", "æ"), ("b", "b"), ("c", "k"), ("d", "d"), ("e", "ɛ"), ("f", "f"), ("g", "ɡ"), ("h", "h"), ("i", "ɪ"),
    ("j", "dʒ"), ("k", "k"), ("l", "l"), ("m", "m"), ("n", "n"), ("o", "ɑː"), ("p", "p"), ("q", "k"), ("r", "ɹ"),
    ("s", "s"), ("t", "t"), ("u", "ʌ"), ("v", "v"), ("w", "w"), ("x", "ks"), ("y", "j"), ("z", "z"),
]


def load_cmudict(path: str) -> dict:
    words = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#")[0].strip()
            if not line:
                continue
            word, *phones = line.split()
            if "(" in word:  # alternative pronunciations: keep the first
                continue
            words[word.lower()] = phones
    return words


def arpa_to_ipa(phones) -> str:
    out = []
    for p in phones:
        base, stress = (p[:-1], p[-1]) if p[-1].isdigit() else (p, "")
        if stress == "1":
            out.append("ˈ")
        elif stress == "2":
            out.append("ˌ")
        out.append(ARPA0.get(base, ARPA[base]) if stress == "0" else ARPA[base])
    return "".join(out)


def letter_rules(word: str) -> str:
    out, i = [], 0
    while i < len(word):
        for graph, ipa in EN_RULES:
            if word.startswith(graph, i):
                out.append(ipa)
                i += len(graph)
                break
        else:
            i += 1
    if word.endswith("e") and len(word) > 2 and out and out[-1] == "ɛ":
        out.pop()  # silent final e
    return "ˈ" + "".join(out) if out else ""


def english_word(word: str, lexicon: dict) -> str:
    if word in lexicon:
        return arpa_to_ipa(lexicon[word])
    if word.endswith("'s") and word[:-2] in lexicon:
        base = arpa_to_ipa(lexicon[word[:-2]])
        return base + ("ɪz" if base[-1] in "szʃʒ" else "s" if base[-1] in "ptkfθ" else "z")
    stripped = word.strip("'")
    if stripped != word:
        return english_word(stripped, lexicon)
    return letter_rules(word)


def english(text: str, lexicon: dict) -> str:
    text = unicodedata.normalize("NFC", text).replace("’", "'")
    # "a.m." / "p.m." and other dotted initialisms: spell the letters.
    text = re.sub(r"\b((?:[A-Za-z]\.){2,})", lambda m: " ".join("#" + c for c in m.group(1).replace(".", "")) + " ", text)
    out = []
    for token in re.findall(r"#[A-Za-z]|[A-Za-z']+|[,.?!;:]", text):
        if token.startswith("#"):
            out.append(" ˈ" + LETTER_NAMES[token[1].lower()] + " ")
        elif token in PUNCT:
            out.append(token)
        else:
            out.append(" " + english_word(token.lower(), lexicon) + " ")
    return tidy("".join(out))


def tidy(phonemes: str) -> str:
    phonemes = re.sub(r"\s+([,.?!;:])", r"\1", phonemes)
    phonemes = re.sub(r"([,.?!;:])(?=[^\s,.?!;:])", r"\1 ", phonemes)
    return re.sub(r"\s+", " ", phonemes).strip()


if __name__ == "__main__":
    lang, text = sys.argv[1], sys.argv[2]
    print(turkish(text) if lang == "tr" else english(text, load_cmudict(sys.argv[3])))

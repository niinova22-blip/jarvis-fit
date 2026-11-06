"""Number words, same rules as SpeechText.spell in the app."""

ONES = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
TENS = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]


def tr_words(n: int) -> str:
    """Turkish number words."""
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


EN_ONES = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
           "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
EN_TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


def en_words(n: int) -> str:
    if n >= 1000:
        return en_words(n // 1000) + " thousand" + (" " + en_words(n % 1000) if n % 1000 else "")
    words = []
    if n >= 100:
        words += [EN_ONES[n // 100], "hundred"]
        n %= 100
    if n >= 20:
        words.append(EN_TENS[n // 10])
        n %= 10
    if n:
        words.append(EN_ONES[n])
    return " ".join(words) or "zero"

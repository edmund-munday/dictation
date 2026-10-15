#!/usr/bin/env python3
"""Voice dictionary plugin; spelling rules mirror DictationCore.SpelledTerm."""

import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile


NAMES = {
    "ay": "a", "bee": "b", "see": "c", "sea": "c", "dee": "d", "ee": "e",
    "ef": "f", "gee": "g", "aitch": "h", "eye": "i", "jay": "j", "kay": "k",
    "el": "l", "em": "m", "en": "n", "oh": "o", "pee": "p", "cue": "q",
    "queue": "q", "ar": "r", "es": "s", "ess": "s", "tee": "t", "tea": "t",
    "you": "u", "vee": "v", "ex": "x", "why": "y", "zed": "z", "zee": "z",
}


def parse(spelling):
    spelling = re.sub(r"\bdouble-u\b", "w", spelling.lower())
    tokens = [token for token in re.split(r"[\s,.\-]+", spelling) if token]
    if not tokens:
        return None
    words = [[]]
    for token in tokens:
        if token == "space":
            words.append([])
        else:
            words[-1].append(token)
    result = []
    for parts in words:
        if not parts:
            return None
        index, mode = 0, None
        if parts[:2] == ["all", "caps"]:
            index, mode = 2, "caps"
        elif parts[0] == "lowercase":
            index, mode = 1, "lowercase"
        word_start = index
        letters, marked = "", False
        while index < len(parts):
            capital, copies = False, 1
            if parts[index] == "capital":
                capital, marked = True, True
                index += 1
            elif parts[index] == "double":
                copies = 2
                index += 1
            if index == len(parts):
                return None
            token = parts[index]
            if token in NAMES:
                letter = NAMES[token]
            elif re.fullmatch(r"[a-z]", token):
                letter = token
            elif ((capital or len(parts) - word_start == 1) and re.fullmatch(r"[a-z]+", token)
                  and token not in {"capital", "double", "all", "caps", "lowercase"}):
                letter = token
            else:
                return None
            letters += (letter[0].upper() + letter[1:] if capital else letter) * copies
            index += 1
        if not letters:
            return None
        if mode == "caps":
            letters = letters.upper()
        elif mode == "lowercase":
            letters = letters.lower()
        elif not marked:
            letters = letters[0].upper() + letters[1:]
        result.append(letters)
    return " ".join(result)


def notify(text):
    print(json.dumps({"notify": text}))


def main():
    payload = json.load(sys.stdin)
    transcript = payload.get("context", {}).get("transcript", "")
    # Use the original transcript: the fast path normalises punctuation in args.
    fillers = r"um|umm|uh|uhh|er|erm|ah|hmm|so|okay|ok|well|hey"
    match = re.fullmatch(
        rf"\s*(?:(?:{fillers})\b[\W_]+)*(add|remove)[\W_]+word\b\s*(.*)",
        transcript, flags=re.IGNORECASE | re.DOTALL)
    term = parse(match[2]) if match else None
    if term is None:
        notify("Couldn't spell that word.")
        return

    support = Path(os.environ.get("DICTATION_SUPPORT_DIR") or
                   Path.home() / "Library/Application Support/Dictation")
    support.mkdir(parents=True, exist_ok=True, mode=0o700)
    dictionary = support / "dictionary.txt"
    # Serialise concurrent invocations; atomic replacement keeps readers safe.
    with (support / ".dictionary.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        terms = dictionary.read_text(encoding="utf-8").splitlines() if dictionary.exists() else []
        kept = [old.strip() for old in terms if old.strip() and old.strip().lower() != term.lower()]
        found = any(old.strip().lower() == term.lower() for old in terms)
        if match[1].lower() == "remove" and not found:
            notify("Not in dictionary: " + term)
            return
        if match[1].lower() == "add":
            kept.append(term)
        descriptor, temporary = tempfile.mkstemp(prefix=".dictionary-", dir=support)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write("".join(item + "\n" for item in kept))
            os.replace(temporary, dictionary)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    notify(("Added: " if match[1].lower() == "add" else "Removed: ") + term)


if __name__ == "__main__":
    main()

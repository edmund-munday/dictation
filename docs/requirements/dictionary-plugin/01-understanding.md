# Understanding

A plugin `dictionary` (plugins folder JSON + executable `bin/dictionary.py`) with triggers "add word {letters}"
and "remove word {letters}", confirm_delay_s 0, matched by the local fast path (R236), so no gateway call. The
script parses the spelled letters deterministically, edits ~/Library/Application Support/Dictation/dictionary.txt
(one term per line, case-insensitive dedupe, newest at the end) and prints {"notify": "Added: Kazey"} /
{"notify": "Removed: Kazey"}; nothing is inserted.

Real whisper output for spelled words (recorded with `say` + small.en, fixtures dict-*.wav):
"Add word K-A-Z-E-Y.", "Add word capital T-E-S-S-A.", "Add word M-O-S-S." (from "M O double S"),
"Add word capital G-R-O-K space capital B-O-T.", "Remove word K-A-Z-E-Y.". Whisper may also produce
"K, A, Z, E, Y", "K. A. Z. E. Y.", "K A Z E Y", "double s", or letter names ("kay", "bee", "see", "why", "zed").

Casing: a word with no "capital"/"all caps"/"lowercase" marker gets first letter upper, rest lower
("K-A-Z-E-Y" -> "Kazey", matching the brief's "Added: Kazey"); with markers only marked letters are upper.

Feeding: the Mac whisper prompt = lead-in "Edmund dictating notes and messages: " + dictionary terms (newest kept
within 600 characters, inside whisper's 224-token prompt limit), read fresh per transcription. The gateway
cleanup system prompt gets a "Preferred spellings" line (newest kept within 1000 characters). Migration creates
dictionary.txt from the current prompt vocabulary when missing. Menu item "Open dictionary".

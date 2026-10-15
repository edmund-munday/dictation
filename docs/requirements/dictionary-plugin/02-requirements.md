# Requirements

Fixtures: Tests/Fixtures/audio/dict-1..6.wav (macOS `say`, 16 kHz mono) and their real whisper-cli small.en
output in Tests/Fixtures/audio/dict-whisper.json: dict-1 "add word K, A, Z, E, Y." -> "Add word K-A-Z-E-Y.";
dict-2 "add word capital T E S S A." -> "Add word capital T-E-S-S-A."; dict-3 "add word M O double S." ->
"Add word M-O-S-S."; dict-4 "add word capital G R O K space capital B O T." -> "Add word capital G-R-O-K space
capital B-O-T."; dict-5 "remove word K A Z E Y." -> "Remove word K-A-Z-E-Y."; dict-6 "add word Q-U-I-N-N." ->
"Add word Q-U-I-N-N.".

- R272 Spelling parser (deterministic; in the plugin script, and the same rules in DictationCore
  `SpelledTerm.parse(_:) -> String?` for tests and reuse): tokens split on whitespace, commas, periods and
  hyphens; single letters and letter names (ay, bee, see/sea, dee, ee, ef, gee, aitch, eye, jay, kay, el, em,
  en, oh, pee, cue/queue, ar, es/ess, tee/tea, you, vee, double-u, ex, why, zed/zee) add a letter; "double x"
  adds x twice; "capital x" adds X; "space" starts a new word; "all caps" uppercases the next word; "lowercase"
  keeps the next word lowercase. Words without markers: first letter upper, rest lower. A run of letters already
  joined ("kazey" from a normaliser, or "GROK" as whisper writes it without the vocabulary prompt) is accepted as that word; "capital GROK" -> "Grok". Any other token -> nil. Pass: "K-A-Z-E-Y" ->
  "Kazey"; "K, A, Z, E, Y" -> "Kazey"; "K. A. Z. E. Y." -> "Kazey"; "capital T-E-S-S-A" -> "Tessa"; "M O double
  S" -> "Moss"; "capital G-R-O-K space capital B-O-T" -> "Grok Bot"; "all caps A P I" -> "API"; "lowercase S C R
  I P T" -> "script"; "kay ay zed ee why" -> "Kazey"; "K A banana" -> nil.
- R273 Add by voice: with the gateway backend on and the dictionary plugin installed, releasing after each
  recorded fixture utterance (dict-1/2/3/4/6 whisper text through HoldPipeline/Session as the app does, then the
  real PluginRunner running the real script with env DICTATION_SUPPORT_DIR pointing at a temp dir) makes zero
  gateway requests, inserts nothing, appends the term to dictionary.txt once (case-insensitive dedupe: adding
  "Kazey" twice leaves one line) and the panel shows "Added: Kazey" (resp. Tessa, Moss, Grok Bot, Quinn).
- R274 Remove by voice: dict-5 removes "Kazey" (case-insensitive) and shows "Removed: Kazey"; removing a term not
  in the file shows "Not in dictionary: Kazey" and leaves the file unchanged. Unparseable spelling shows
  "Couldn't spell that word." and changes nothing.
- R275 Whisper prompt: each transcription's prompt is "Edmund dictating notes and messages: " + terms joined
  with ", " + "." read from dictionary.txt at that moment (newest last); over 600 characters, the oldest terms
  are dropped first. Pass: after adding "Quinn" the next transcription's --prompt contains "Quinn"; with 200
  long terms the prompt is <= 600 chars and contains the newest term. Tail-transcription prompts (R260) use
  this prompt as the vocabulary part.
- R276 Gateway prompt: the cleanup system prompt (full and per-sentence calls) gets a line "Preferred spellings
  (use exactly when these words are meant): t1, t2, ..." (newest kept within 1000 characters); absent when the
  dictionary is empty or missing. Pass: the scripted gateway transport sees the line with "Kazey".
- R277 Migration: when dictionary.txt does not exist it is created from the comma-separated terms after the
  colon in the current whisper prompt (user `whisperPrompt` default if set, else the built-in default), so Kazey,
  script and Snip and the other built-in terms are in it. An existing file is never overwritten.
- R278 Menu item "Open dictionary" opens dictionary.txt (migrating first if missing).
- R279 The plugin ships as examples/plugins/dictionary.json + examples/plugins/bin/dictionary.py (triggers "add
  word {letters}", "remove word {letters}", confirm_delay_s 0) and is installed into the Mac plugins folder; the
  fast path handles it with no gateway call.

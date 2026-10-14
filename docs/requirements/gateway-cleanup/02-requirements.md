# Behaviours

- G1 (R201) Default backend: with no other choice made, the app's cleanup selection is the gateway (backend `.gateway`,
  menu label mentions "gateway" and the model). CLIs are not the default.
- G2 (R202) Request: GatewayCleaner POSTs to `<url>/v1/chat` with `Authorization: Bearer <key>`, JSON body containing the
  configured `model`, a system message holding the cleanup prompt and a user message holding the raw transcript,
  and a positive `max_output_tokens`. Model is configurable (config value appears in the request).
- G3 (R203) Success: a 200 response `{"text":"..."}` inside the deadline -> the cleaned text is what gets inserted
  (same insertion/copy-fallback path as before; trailing newlines stripped, never a Return).
- G4 (R204) Timeout: no response within 3 s of release -> local rule-based cleanup is inserted; a late response is ignored.
- G5 (R205) HTTP error (non-2xx, transport error, or a body without `text`) -> local rule-based cleanup is inserted.
- G6 (R206) Config: loaded from a JSON file at an injectable path; missing file or missing key -> gateway unavailable,
  local rules used; the key never appears in the repo.
- G7 (R207) Prompt: the cleanup prompt requires aggressive cleanup keeping the speaker's voice and exact meaning, resolving
  self-corrections ("actually I mean", "scratch that"), auto-punctuation, spoken punctuation kept as words, and no
  trailing newline/Return.
- G8 (R208) Test command: `scripts/test.sh` runs `swift test` and `swift test --filter DictationMacTests`, exits non-zero if
  either fails.
- G2b (R209) Bug: the gateway rejects max_output_tokens above its server ceiling of 1000 (HTTP 400), so every request fell back. The request's max_output_tokens must be between 1 and 1000.

## Follow-up (Edmund, 2026-10-14 12:58): "make the prompt firmer about spoken punctuation, add an example pair, and add a check after cleanup that uses the local rules if a spoken-punctuation word was dropped; send temperature 0 from the app"
- R210 Prompt: CleanupPrompt.text explicitly lists the spoken punctuation words "comma", "full stop", "period", "question mark", "exclamation mark", "new line", "new paragraph", says they are kept exactly as words (never converted to symbols or line breaks, never dropped), and contains one example input/output pair showing a spoken punctuation word kept.
- R211 Guard: if the raw transcript contains a spoken-punctuation word (case-insensitive, whole words; list as in R210) and the LLM result (gateway or CLI) contains fewer occurrences of it, the result is rejected and the local rule-based cleanup is inserted instead. A result that keeps them is inserted as before.
- R212 The gateway request body includes "temperature": 0.

## Follow-up (Edmund, 2026-10-14 13:16): "cleanup is massaging the text too much. It must be MINIMAL: only fix bad grammar, remove fillers and stutters, and apply self-corrections. Keep his exact words, tone and directness otherwise; never soften, rephrase, add hedges or add words. Example: 'push the release to thursday actually i mean friday' must become 'Push the release to Friday.' and NOT 'I was thinking we should push the release to Friday.'"
- R213 Prompt: CleanupPrompt.text says cleanup is minimal (only fix bad grammar, remove fillers and stutters, apply self-corrections), keep the speaker's exact words, tone and directness, and never soften, rephrase, add hedges or add words; it includes the example input "push the release to thursday actually i mean friday" with output "Push the release to Friday." The R210 spoken-punctuation rule and example stay.

## Reversal (Edmund, 2026-10-14 13:31): spoken punctuation becomes marks
"Spoken punctuation words must now become the actual marks: comma becomes ',', full stop/period becomes '.', question mark becomes '?', exclamation mark becomes '!', new line becomes a line break, and new paragraph becomes a blank line. These line breaks are fine because they're text inside the field, not a Return keypress that submits. Never press Return/Enter as a key event ... Also, the model should add its own punctuation (commas, full stops, question marks, capitals) wherever proper grammar needs it. The minimal-cleanup rule otherwise stays."
- R210, R211 and the original R75 ("spoken punctuation stays words") are SUPERSEDED; their tests are removed.
- R214 Local rules convert spoken punctuation: comma -> ",", full stop/period -> ".", question mark -> "?", exclamation mark -> "!", new line -> "\n", new paragraph -> "\n\n" (case-insensitive, whole words); the next word after . ? ! or a line break is capitalised; the inserted text never ends with a line break.
- R215 Prompt: tells the model to convert those words to marks / a line break / a blank line, to add its own punctuation and capitals where grammar needs it, keeps the minimal rule (R213), and its example shows "send the deck comma thanks" -> "Send the deck, thanks."; it no longer says to keep them as words.
- R216 A gateway result that turned spoken punctuation into marks is inserted (no after-cleanup rejection).
- R217 Newline safety: line breaks are inserted as text in multi-line fields (text areas); in single-line fields, combo boxes and terminals they become spaces (existing R43 behaviour); no key events (Return) are ever emitted.

## Edmund, 2026-10-14 14:24-14:26: auto-send, don't-send, emphasis words, quotes
- R223 REPLACES the "never press Return" rule FOR CHAT APPS ONLY: after a confirmed insert into a chat app (bundle ids: Grok Bot com.anysphere.sand, Slack, Messages, WhatsApp, Discord, Telegram, Signal, Teams, Messenger; extra ids via the `autoSendExtraChatApps` default; browsers not included), press a single Return about 150 ms later. Never when the insert failed, the text is empty, or the capture was cancelled. Menu toggle "Auto-send in chat apps" (default on, `autoSendInChatApps`). Everywhere else Return is still never pressed. Line breaks inside the message are inserted as text (paste), so they never send mid-message.
- R222 A "don't send" instruction at the END of the utterance ("oh actually don't send this", "don't send it yet", "hold off sending", "no send") is stripped and blocks auto-send. The gateway flags it with [[NOSEND]]; a regex on the raw transcript is the backstop; either one blocks. A mid-message "don't send the invoice until Friday" is content.
- R224 Emphasis and meaning words (actually, really, just, literally, basically, honestly, meaningful like) and swearing are kept; only true fillers (um, uh, er), stutters and self-correction cues are removed.
- R225 Spoken "quote" is markup: cues become ⟦QUOTE⟧ / ⟦/QUOTE⟧ tokens before the gateway (noun uses like "a quote for the job" are left alone); the model wraps the quoted chunk in straight double quotes, inferring the end when there is no close cue. Local rules handle explicit pairs and run an unclosed quote to the sentence end. Tokens are stripped from anything inserted.

## Edmund, 2026-10-14: tuning corpus
- R228 REPLACES R89 ("No transcript log is written") and the brief's "no transcript logging" for the tuning corpus only. Each completed or cancelled utterance appends one JSON line to `~/Library/Application Support/Dictation/corpus/YYYY-MM.jsonl` (directory 0700, files 0600). Keys: timestamp (ISO 8601), raw, tokenized, cleaned, backend (gateway/local/cli/none), latencyMs, app (frontmost bundle id), field (FieldRole name), inserted, autoSent, noSend, cancelled. Text only, never audio; password and secure fields are never logged. Menu toggle "Save dictations for tuning" (default on, `saveDictationsForTuning`); off writes nothing. Menu item "Reveal dictation log folder" opens it in Finder. Audio is still never stored.

## Edmund, 2026-10-14 14:46: voice-command plugins v1 (design: dictation-plugins-design.md; NO wake word)
- R229 One JSON file per plugin in `~/Library/Application Support/Dictation/plugins/` (name, description, enabled, triggers, args {type, required, description, default}, action {type: exec, path (relative = plugins folder), argv}, timeout_s default 10, max 120). Bad files are skipped and listed with ⚠︎; files not owned by the user or world-writable are refused. JSON chosen over YAML to avoid a dependency.
- R230 Local fallback when the gateway fails or times out: trigger templates match exactly (case/punctuation-insensitive), with a trailing `{arg}` taking the rest of the phrase. Required args must be present.
- R231 Detection rides the single gateway cleanup call: with ≥1 enabled plugin the prompt lists the plugins and the model returns `{mode, plugin, args, confidence, text}`. A command runs only at confidence ≥ 0.8 with a known, enabled plugin and valid args; otherwise `text` is typed as dictation. No wake word/prefix. When unsure, it's dictation.
- R232 A command utterance is never typed and never auto-sent. The panel shows "Running: <plugin>" for a 1.5 s cancel window; any key cancels ("Cancelled: <plugin>"). Commands never run when the focused field is secure. A command needs no focused text field.
- R233 Plugin stdout JSON `{insert?, notify?, send?}`: insert goes through normal insertion (auto-send only when `send: true`), notify shows in the panel. Exit 1 shows stderr's first line; exit 2 types the transcript instead. Corpus records (R228) get `mode` (dictation|command) and `plugin`.
- R234 Exec runner: run directly via Process (never a shell); `{arg}` substituted per argv element; stdin `{plugin, args, context, version: 1}`; env DICTATION_PLUGIN, DICTATION_ARG_<NAME>, DICTATION_APP_BUNDLE, DICTATION_DISPLAY_ID, DICTATION_VERSION; timeout kills the process (group).
- R235 Shipped plugins (installed once, never overwriting edits): `echo` ("test echo <text>" types the text back) and `screenshot` ("take a screenshot", "take a screenshot of X", "grab a screenshot", "screenshot this"): v1 runs `screencapture -c -x` (full screen to clipboard); `subject` is passed through for future cropping. Snip has no CLI or URL scheme yet (inspected read-only), so it is not used; Snip would need `snip capture --describe <text> --out clipboard --json` or `snip://capture`.
- Menu: Plugins submenu with an enable/disable toggle per plugin, Reload plugins, Open plugins folder.

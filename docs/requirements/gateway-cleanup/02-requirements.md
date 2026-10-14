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

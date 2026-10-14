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

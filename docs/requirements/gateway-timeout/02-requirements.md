# Requirements

- R280 Timeout: GatewayConfig's default `timeoutSeconds` (missing in gateway.json, or init default) is 5 s
  (was 3). The release call and background sentence calls use it (request timeoutInterval, timeout_ms in the
  body, and the Session deadline). Pass: a config decoded without timeoutSeconds has 5; a scripted gateway reply
  arriving at 4.0 s after release is used (inserted text is the gateway's), and one at 5.5 s falls back to
  local rules at 5 s. An explicit timeoutSeconds in gateway.json still wins.
- R281 Outcome logging: each utterance record (UtteranceRecord and the corpus JSONL line) carries
  `cleanupOutcome`: "gateway" (a gateway reply was accepted and used, even if identical to local rules),
  "timeout" (no reply before the deadline), "error" (transport/HTTP error or empty reply), "rejected" (reply
  refused by acceptLLMResult: empty, too long, "here is"/"sure" preamble), "local" (gateway not used: backend
  off/local, fast path, command), and the `backend` field becomes "gateway" whenever the gateway reply was used.
  Pass (scripted gateway transport through the Session as the app drives it): identical-text reply -> backend
  "gateway", cleanupOutcome "gateway"; no reply -> "timeout" and local text; HTTP 503 -> "error"; reply "Here is
  the text: ..." -> "rejected"; gateway off -> "local". Corpus line on the Mac includes cleanupOutcome.
- R282 Incremental cleanup R249-R256 tests stay green with the new default (background calls use the same
  deadline).

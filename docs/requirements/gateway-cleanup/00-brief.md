# Gateway cleanup — brief (Edmund, 2026-10-14, relayed via Dictation Builder)

"Make the LLM gateway the DEFAULT cleanup backend for now. Currently cleanup on release goes to grok/claude/cursor-agent CLIs (6-36s, too slow, 4s deadline, so a local rule-based fallback almost always wins). Keep the local rule-based fallback; keep the CLIs as optional non-default backends."

Details from the request:
- GatewayCleaner backend in core (URLSession is Foundation, OK), with the same cleanup prompt (aggressive cleanup, keep Edmund's voice and exact meaning, resolve self-corrections like 'actually I mean' / 'scratch that', auto-punctuate, spoken punctuation stays words, never add a trailing newline/Return). Pick the fastest good model the gateway offers; make the model configurable.
- Make it default; deadline about 3s, then fall back to local rules. Keep the copy-fallback/insertion behaviour unchanged. No audio/transcript logging.
- Tests with a stubbed HTTP layer: success, timeout -> fallback, HTTP error -> fallback, default backend is gateway. No tests depending on the live server, fixed ports or machine state.
- Store config on the Mac in a config file or Keychain, not hardcoded in the repo.
- Add scripts/test.sh running `swift test` AND `swift test --filter DictationMacTests`; update docs.

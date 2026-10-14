# dictation

Voice dictation for macOS with local speech recognition and gateway cleanup by default.

Cleanup uses the LLM gateway when configured, with local rule-based cleanup on failure
or after a three-second deadline from release. Without gateway configuration it uses
local rules. The grok, Claude, and Cursor CLIs remain optional backends available via
the menu's re-choose action; the app does not probe them at launch.

Create `~/Library/Application Support/Dictation/gateway.json` on the Mac:

```json
{
  "url": "https://your-gateway-host",
  "model": "deepseek/deepseek-flash",
  "key": "your-gateway-key",
  "timeoutSeconds": 3
}
```

Protect the file with `chmod 600 "$HOME/Library/Application Support/Dictation/gateway.json"`.
`url` is the gateway base URL (cleanup POSTs to `<url>/v1/chat`), and `key` is required.
`model` and `timeoutSeconds` are optional, defaulting to `deepseek/deepseek-flash` and
3 seconds. Missing or malformed configuration, including an empty key, selects local
rules. Keep the key out of the repository. Transcripts and cleanup results are never logged.

The official test command on macOS is `scripts/test.sh`. It runs both `swift test` and
`swift test --filter DictationMacTests`; plain `swift test` skips `DictationMacTests`.

## Brief (Edmund's words, verbatim)

> macOS tool that effectively replaces the keyboard with voice dictation in any text input field (mouse/keyboard still available). Entirely automated start: always listening, with an on/off toggle, built assuming it is ON far more than just when typing, so it must cope with speech not meant for a text field. Low latency is a big consideration. Cleanup: fix what he says including self-corrections like 'actually, I mean xyz', producing exactly what he intended without changing meaning. Runs on his MacBook first, work laptop later, so fully local: self-hosted models, or Cursor CLI / Claude CLI as backing tool; no cloud. English assumed (unconfirmed).

See `docs/requirements.md`.

# Requirements

- R283 Subject gate: PluginSpec arg option `ignore_words` (list of strings, default empty). A command arg value
  whose normalised words (lowercase, punctuation removed) are all in that list is dropped before the command
  request is queued (fast path and gateway path alike): no DICTATION_ARG_<NAME> env, absent from context args.
  Values with any other word are kept as spoken (trimmed). Pass: through Session + real PluginRunner with a
  recording script: "Take a screenshot." -> no subject; "Take a screenshot of this." -> no subject; "Um,
  screenshot this." -> no subject; "Take a screenshot of the screen." -> no subject; "Screenshot the Slack
  window." -> subject "Slack window" (compare case-insensitively: the fast path may lowercase); "Screenshot that chart." -> subject "chart" (the trigger "screenshot that {subject}" consumes "that");
  "Screenshot that." and "Screenshot that, um." -> no subject, fast path, no gateway call; "Take a screenshot of
  the error dialog." -> subject "the error dialog". The bare "Screenshot that." case is served by the exact
  trigger "screenshot that"; a {placeholder} trigger still needs at least one word after it (R236 unchanged).
- R284 Per-args timeout: PluginSpec `timeout_with_args_s` (optional). When any optional arg survives the gate
  the runner uses it instead of timeout_s. Pass: screenshot with subject runs under a 40 s limit (a script
  sleeping 20 s completes); without subject the 15 s limit applies (a 20 s script is killed).
- R285 Script examples/plugins/bin/snip-capture.py (installed to the plugins folder; screenshot.sh untouched):
  calls `$SNIP_BIN` (default ~/bin/snip) `capture --out clipboard --json`, adding `--describe <subject>` only
  when DICTATION_ARG_SUBJECT is non-empty, and removes DICTATION_ARG_SUBJECT from Snip's environment when it is
  empty. Output: ok without subject -> {"notify":"Screenshot copied to clipboard"}; ok + cropped ->
  {"notify":"Screenshot of <subject> copied to clipboard"}; ok + cropped=false -> {"notify":"Full screenshot
  copied: <reason>"}; exit 69 -> "Snip isn't running"; 75 -> "Snip timed out"; other -> "Snip capture failed
  (<rc>)" on stderr with exit 1. Pass with a fake snip binary recording argv/env and printing the JSON.
- R286 Panel: the cropped=false reason reaches the panel as plain text through the notify path (no markup
  interpretation). Pass: Session/PluginRunner flow shows "Full screenshot copied: <reason>".
- R287 Manifest: examples/plugins/screenshot.json uses bin/snip-capture.py, timeout_s 15, timeout_with_args_s
  40, confirm_delay_s 0, the ignore_words list from 01-understanding.md for subject, and triggers "take a
  screenshot", "take a screenshot of {subject}", "grab a screenshot", "grab a screenshot of {subject}",
  "screenshot", "screenshot this", "screenshot that", "screenshot the {subject}", "screenshot that {subject}". Fast path still
  makes no gateway call.
- R288 Real sample: recorded "take a screenshot of the Slack window" and "take a screenshot of this" (say + real
  whisper) through the pipeline with a fake snip yield --describe with "the Slack window" (case-insensitive) and no --describe
  respectively.

- R294 Gate placement: the gate lives in PluginSpec.validated(_:) in Sources/DictationCore/Plugins.swift,
  shared by TriggerMatcher.match and CommandRouter.parse, before CommandMatch/CommandRequest exist. Trim
  the value, normalise with TriggerMatcher.words (also normalise each ignore_words entry with that same
  function), and drop values with zero words or with every word in the list. Then apply the existing
  default/required logic: a dropped required arg returns nil (dictation fallback); a dropped arg with a
  default gets its default. PluginArg has an explicit CodingKey ignoreWords = "ignore_words", default [].
  Do not add ignore_words to promptSection. PluginSpec.parse rejects an arg setting both default and
  ignore_words (including an explicitly empty list).
- R295 Timeout rule: PluginSpec.timeoutWithArgsSeconds decodes optional timeout_with_args_s, clamped to
  0.1–120 seconds like timeout_s. Pure timeout(for args: [String: String]) -> Double returns
  timeoutWithArgsSeconds ?? timeoutSeconds when any non-required arg key is present in args, otherwise
  timeoutSeconds. PluginRunner uses spec.timeout(for: args) with the already gated args it received.
  No timeout logic belongs in AppModel.
- R296 Clean environment: PluginRunner builds the child environment in a pure static function taking
  base: [String: String], removing only runner-owned inherited keys before setting this invocation's
  values: every DICTATION_ARG_* key plus DICTATION_PLUGIN, DICTATION_VERSION, DICTATION_APP_BUNDLE,
  DICTATION_DISPLAY_ID, DICTATION_SELECTED_TEXT, DICTATION_MEDIA_WAS_PLAYING, and DICTATION_APP_RESOURCES.
  Any other inherited DICTATION_* key (e.g. DICTATION_SUPPORT_DIR, DICTATION_MEDIA_CMD) passes through unchanged.
- R297 Wrapper safety: examples/plugins/bin/snip-capture.py reads args.subject from the stdin JSON payload,
  not the environment. It never uses argparse or exits 2 (AppModel inserts the transcript on exit 2).
  Every failure, including bad stdin, exits 1 with one line on stderr. It forwards SIGTERM to the snip
  child and waits for it. Its subprocess timeout is below timeout_with_args_s: default 38 seconds,
  overridable by SNIP_CAPTURE_TIMEOUT_S for tests; expiry kills and waits for snip and reports
  "Snip timed out", exit 1. Find snip by absolute path: $SNIP_BIN, else ~/bin/snip, /opt/homebrew/bin/snip,
  ~/.local/bin/snip; if none exists report "snip not found", exit 1. Manifest argv stays [] (no subject
  placeholder); add --describe only for a non-empty subject. Remove inherited DICTATION_ARG_SUBJECT
  from snip's environment when no subject is present. This stdin rule supersedes R285's env input rule;
  R285's notify and exit 69/75/other messages stay unchanged. No full-screenshot fallback for 75 or 70
  pending Edmund's decision.
- R298 Shipping: examples/plugins/screenshot.json is a full replacement with name "screenshot" per R287.
  examples/plugins/README.md instructs copying bin/snip-capture.py into the plugins folder's bin/ and
  backing up the installed screenshot.json before replacing it. Do not change BundledPlugins.screenshotJSON
  or touch any screenshot.sh.
- R305 Named capture fallback (supersedes R297's pending fallback decision and named-call timeout):
  When a subject is present and the `--describe` Snip call exits 75 (timeout) or 70 (capture failure),
  or the wrapper's own deadline for that call expires, kill and reap that child and make exactly one
  plain capture using the same argv without `--describe <subject>`. SIGTERM cancellation must never
  trigger fallback. On fallback success, print
  {"notify":"Full screenshot copied to clipboard. Couldn't crop to <subject>."} and exit 0.
  The describe deadline is 31 seconds and the fallback deadline is 6 seconds, keeping capture and
  cleanup under the manifest's 40-second limit. Tests may shorten these with SNIP_CAPTURE_TIMEOUT_S
  and SNIP_FALLBACK_TIMEOUT_S, capped at 31 and 6 seconds respectively.
  Exit 69 (Snip not running), exit 64, invalid JSON or ok!=true from the describe call, cancellation,
  and bare requests (no subject) get no fallback and retain their existing behaviour. If fallback
  itself fails, exit 1 with exactly one stderr line: "Screenshot failed. Nothing was copied." Never
  exit 2. The cropped=false notification behaviour in R286 stays unchanged.

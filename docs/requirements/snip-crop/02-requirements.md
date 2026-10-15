# Requirements

- R283 Subject gate: PluginSpec arg option `ignore_words` (list of strings, default empty). A command arg value
  whose normalised words (lowercase, punctuation removed) are all in that list is dropped before the command
  request is queued (fast path and gateway path alike): no DICTATION_ARG_<NAME> env, absent from context args.
  Values with any other word are kept as spoken (trimmed). Pass: through Session + real PluginRunner with a
  recording script: "Take a screenshot." -> no subject; "Take a screenshot of this." -> no subject; "Um,
  screenshot this." -> no subject; "Take a screenshot of the screen." -> no subject; "Screenshot the Slack
  window." -> subject "Slack window" (compare case-insensitively: the fast path may lowercase); "Screenshot that chart." -> subject "that chart"; "Take a screenshot of
  the error dialog." -> subject "the error dialog".
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
  "screenshot", "screenshot this", "screenshot the {subject}", "screenshot that {subject}". Fast path still
  makes no gateway call.
- R288 Real sample: recorded "take a screenshot of the Slack window" and "take a screenshot of this" (say + real
  whisper) through the pipeline with a fake snip yield --describe with "the Slack window" (case-insensitive) and no --describe
  respectively.

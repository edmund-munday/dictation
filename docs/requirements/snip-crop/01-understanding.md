# Understanding

Today screenshot.json (user plugins folder) has triggers "take a screenshot", "take a screenshot of {subject}",
"grab a screenshot", "grab a screenshot of {subject}", "screenshot this", "screenshot the {subject}",
timeout_s 15, and runs bin/screenshot.sh, which calls `snip capture --out clipboard --json`. PluginRunner sets
DICTATION_ARG_SUBJECT when the fast path or gateway fills {subject}, and Snip now reads that env itself, so
today "take a screenshot of this" would already send subject "this" to Snip and the 15 s timeout would kill a
crop.

Standing rule: leave the user's plugins/bin/screenshot.sh alone. So the new behaviour lives in a new script
bin/snip-capture.py (examples/plugins/bin/ and installed), and screenshot.json (examples + installed) points to
it; screenshot.sh stays untouched on disk.

Subject gate (Core, applies to fast-path and gateway-produced commands): an optional arg may declare
`"ignore_words": [...]` in the plugin JSON. After lowercasing and dropping punctuation, if every word of the
value is in that list, the arg is treated as absent (no env var, no context arg). The screenshot plugin lists
fillers and deictics: um, uh, er, like, so, just, please, this, that, it, here, there, the, a, an, my, whole,
entire, full, screen, everything, now. "screenshot the Slack window" -> subject "Slack window"; "screenshot that
chart" -> "that chart"; "take a screenshot of this" / "of the screen" / "um" -> no subject.

Timeout: plugin JSON `timeout_with_args_s` (optional) is used instead of timeout_s when any optional arg is
present after the gate; screenshot uses timeout_s 15, timeout_with_args_s 40.

Script: runs `~/bin/snip capture --out clipboard --json` plus `--describe "<subject>"` only when
DICTATION_ARG_SUBJECT is set and non-empty; clears DICTATION_ARG_SUBJECT from Snip's environment otherwise.
Parses the JSON: ok && cropped -> notify "Screenshot of <subject> copied to clipboard"; ok && no subject ->
"Screenshot copied to clipboard"; ok && subject && cropped=false -> notify "Full screenshot copied: <reason>"
(reason as plain text). Exit codes 69/75/other -> same messages as screenshot.sh.

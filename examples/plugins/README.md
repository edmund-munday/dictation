# Example plugins
Copy into ~/Library/Application Support/Dictation/plugins/ (json 0600, bin 0700). volume, media (needs manages_media + Dictation's mediactl.dylib), rewrite (needs_selection; reads gateway.json, never prints the key).

`dictionary.json` + `bin/dictionary.py` also ship with the app and are installed automatically, preserving existing files. Requires Python 3 with no third-party dependencies. Say “add word K A Z E Y” or “remove word K A Z E Y”; the panel confirms the change without inserting text or calling the gateway. Commas, periods and hyphens between letters, letter names (“kay”, “bee”, “double-u”), “double s”, “capital”, “all caps”, “lowercase”, and “space” for multi-word terms are supported. Unmarked words use an initial capital: “K-A-Z-E-Y” becomes “Kazey”.

Terms live in `~/Library/Application Support/Dictation/dictionary.txt`, one per line, with case-insensitive deduplication and the newest addition last. Use **Open dictionary** in the menu to edit it. On first launch, the app migrates vocabulary from the `whisperPrompt` preference (or its built-in default) without overwriting an existing dictionary. Whisper and gateway cleanup read edits on each call, keeping the newest whole terms within their prompt budgets. For isolated script runs, `DICTATION_SUPPORT_DIR` overrides the support directory.

To enable Snip cropping, back up the installed `screenshot.json` in
`~/Library/Application Support/Dictation/plugins/` before replacing it with this folder's
`screenshot.json` (a full replacement named `screenshot`). Copy `bin/snip-capture.py` into the
plugins folder's `bin/` and make it executable (JSON 0600, script 0700). Requires Python 3 and Snip
with `capture --describe` support. Leave any existing `screenshot.sh` alone; the bundled screenshot
manifest is unchanged, so install this replacement explicitly.

Say “screenshot that chart” or “take a screenshot of the Slack window” to request a crop;
“screenshot”, “screenshot that”, and “take a screenshot of this” capture the whole screen.
If Snip cannot crop, the panel shows its reason as text. Full captures keep the 15-second plugin
timeout; subjects use 40 seconds, with the wrapper stopping Snip after 38 seconds.
The wrapper finds Snip at `$SNIP_BIN` (an absolute path), otherwise `~/bin/snip`,
`/opt/homebrew/bin/snip`, or `~/.local/bin/snip`, in that order.

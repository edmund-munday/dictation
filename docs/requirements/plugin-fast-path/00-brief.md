# Brief (Edmund, 2026-10-14, verbatim via task)
Goal: cut the time from key release to plugin execution for commands such as 'take a screenshot', which currently takes about 4 s (about 1.4 s gateway classification, 1.5 s cancel window, 1.1 s Snip).
1. Local fast path: before calling the gateway, normalise the transcript (lowercase, strip punctuation and leading fillers) and match it against plugin trigger templates (including {arg} slots). On an unambiguous match, run the plugin immediately and skip the gateway. Otherwise keep the existing gateway flow.
2. Per-plugin cancel window: add an optional plugin JSON field (e.g. "confirm_delay_s", or "safe": true) that defaults to the current 1.5 s. Set it to 0 for the screenshot plugin (at ~/Library/Application Support/Dictation/plugins/screenshot.json on the Mac, and in any bundled default copy in the repo). The echo plugin can also be 0.
Add unit tests for both changes.

# Brief (Edmund, 15 Oct 2026 5:10 PM Melbourne, via Tool Builder; ticket tsk_64b0045d)

Hook up Snip cropping. The Snip CLI (main 5e1a0f7, ~/bin/snip) now supports `snip capture --describe "<subject>"` (or DICTATION_ARG_SUBJECT). It returns JSON {ok, path, cropped, reason, fullPath}, waits up to 30 s (about 9 s typical) with a subject and 10 s without, and exit codes are unchanged (0/64/69/70/75). Show `reason` as display text only.
Rule: only pass a subject when what Edmund said actually names something to capture (e.g. 'screenshot the Slack window', 'screenshot that chart'). A bare 'take a screenshot', 'screenshot' or 'screenshot this' must use the fast full-screen path with no --describe. Make sure no subject is passed accidentally, e.g. from leftover filler words.
Raise the plugin's timeout to above 30 s for the subject path only. When cropped=false, show the reason in the panel. Tests first, using Codex.

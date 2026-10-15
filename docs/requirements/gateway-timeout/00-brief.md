# Brief (Edmund, 15 Oct 2026 3:45 PM Melbourne, via Tool Builder; ticket tsk_a1edcb33)

Dictation falls back from the gateway to the local rules too often, so loosen the timeout (currently 3 s). Do this before the dictionary plugin, since it's small.
1. Mine the Mac corpus (~/Library/Application Support/Dictation/corpus/2026-10.jsonl) and any app logs. Find the fallback rate and its cause: timeout vs error vs output rejected (e.g. by the 'here is'/length guard). Also find the gateway latency distribution since the move to the PC (p50/p90/p99), split by input length.
2. Set the timeout from that data, e.g. comfortably above p99 for long dictations, perhaps scaled by input length. If the fallbacks come from rejection or errors rather than the timeout, fix that cause instead.
3. Also check the background per-sentence calls aren't being starved by the at-most-2 concurrency.
Test-first and use Codex as usual. Report the before/after fallback rate and the new timeout.

# Understanding

Today: while the talk key is held, `HoldPipeline.partialTick` (every ~0.8 s) re-transcribes the whole audio
snapshot with whisper-cli (`-nt`, no timestamps). On release `HoldPipeline.end` re-transcribes the whole snapshot
again (~1.2 s for a 20-30 s hold), and that text is the final transcript handed to the session. That final whisper
pass dominates release-to-insert (~2.3 s total).

Change: the partial runs also report whisper segments with start/end times. A sentence (text up to `.`, `?`
or `!` that ends a segment) whose text and end time stay the same over 2+ consecutive partials is stable. The
stable prefix is everything up to the last stable sentence, with its audio end offset. On release, whisper runs
only on audio from (offset - overlap) to the end, prompted with the vocabulary hint plus the stable prefix; the
tail text is joined onto the prefix with duplicated overlap words removed. That joined text replaces the full
final pass as the final transcript. Everything after (session ingest, incremental cleanup R249-R256, fast path,
plugins, insert) is unchanged.

Fallback to today's full pass when: setting off; transcriber without segment support; no stable sentence; hold
shorter than a minimum (short dictation); tail shorter or longer than limits; tail result empty, failed, or
suspicious (e.g. contains whisper hallucination markers, or the join leaves nothing new while audio is long).

Where logic lives: the stable-sentence tracker, the tail plan (offset/fallback decision) and the join/dedupe are
pure and go in DictationCore (testable on Linux with recorded segment partials). Whisper segment parsing and the
pipeline wiring go in DictationMac. A menu toggle in DictationApp, persisted in UserDefaults.

Default: decided after measuring WER of tail-joined vs full on the four WAV fixtures; on if no meaningful word
changes, otherwise off.

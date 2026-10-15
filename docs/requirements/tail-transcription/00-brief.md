# Brief (Edmund, 15 Oct 2026 2:50 PM Melbourne, via Tool Builder; ticket tsk_934bdf93)

On key release, transcribe only the audio after the last stable/finished sentence.

1. Track the audio offset where each finished sentence ends, using whisper segment timestamps from the partial runs.
2. A sentence is stable once its text is unchanged across 2 or more consecutive partials; keep the prefix up to the last stable sentence.
3. On release, run whisper only on the audio after that offset, with a small overlap or padding. Pass the stable prefix as prompt context plus the existing vocabulary hint. Join the tail onto the prefix and remove duplicated words.
4. Fall back to full re-transcription when there is no stable sentence, the tail is too short or long, the result looks off, or the dictation is short. Today's behaviour must not change in those cases.
5. The incremental cleanup from 9a956a6 keeps working.
6. Write requirements and scenario tests first, using the WAV fixtures.

Measure before vs after with the latency bench: release-to-insert ms and the word error rate of tail-joined vs full re-transcription. If accuracy degrades noticeably (for example any meaningful word changes), merge behind a default-off setting and report the numbers for Edmund to decide. Otherwise default it on.

Codex writes the code via agentrun.

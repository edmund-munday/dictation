# Requirements

Fixture: `Tests/Fixtures/audio/whisper-segments.json` — for each WAV (long-dictation, long-scratch, long-plain,
short-dictation) real whisper-cli (small.en q5_1, vocab prompt) output on growing prefixes every 0.8 s:
`{interval_s, duration_s, partials:[{t, segments:[{start,end,text}], stdout}], final_segments, final_stdout}`.

- R258 Segment output: the whisper transcriber can return segments with start/end seconds parsed from
  whisper-cli timestamped output (`[hh:mm:ss.mmm --> hh:mm:ss.mmm]  text`); annotations ([BLANK_AUDIO], (wind))
  are dropped as today; the plain text equals today's parseOutput of the same run. Pass: recorded `final_stdout`
  of each fixture parses to the recorded segments and the same text as `-nt` output joined.
- R259 Stability: replaying the recorded partials of long-dictation / long-plain / long-scratch through the
  tracker yields a stable prefix that (a) only contains whole sentences, (b) each was unchanged in text and end
  time across >= 2 consecutive partials, (c) is a prefix of the next partials' text, and (d) has an audio end
  offset equal to the end time of its last segment. A sentence that changes resets its stability and everything
  after it. short-dictation never yields a stable prefix before release.
- R260 Release on a long hold with a stable prefix (setting on): the pipeline runs whisper once on release, on
  audio starting at (stable offset - overlap, overlap 0.3-1.0 s) only, with prompt = vocabulary hint followed by
  the stable prefix text; the final transcript ingested is prefix + tail with duplicated boundary words removed
  (no word repeated at the join, no word lost). Pass (Mac, HoldPipeline, replayed long-plain.wav and
  long-dictation.wav, real whisper-cli when installed): release transcribes fewer samples than the full snapshot,
  and the inserted/final text has word error rate <= 5% vs the full re-transcription of the same audio and keeps
  every content word of the last sentence (e.g. "Thursday", "not Friday").
- R261 Fallbacks reproduce today exactly: setting off; transcriber without segment support; no stable sentence
  (short-dictation.wav); hold < 6 s; tail < 1.0 s or > 20 s of audio; tail transcription nil/empty; joined
  result suspicious (tail empty of new words while tail audio >= 1.5 s, or tail text repeats the prefix). In each
  case one full-snapshot transcription runs on release with today's prompt and the ingested final text equals
  today's. Pass: transcriber call log on release shows the full sample count and the default prompt.
- R262 Join/dedupe: joining prefix and tail removes the longest overlap (up to 8 words, case- and
  punctuation-insensitive) between the end of the prefix and the start of the tail; capitalisation and
  punctuation of the prefix are kept; single space separation.
- R263 Incremental cleanup still works: with gateway cleanup on and tail transcription on, replaying
  long-dictation partials still sends background sentence requests (R249) and the release request covers only
  the uncleaned tail or the full text per R250/R251; the inserted text matches the R250/R251 expectations.
- R264 Setting: "Fast release transcription" menu toggle in DictationApp persisted under UserDefaults key
  `tailTranscriptionOnRelease`; default set by measurement (see brief). HoldPipeline reads it via an injected
  flag so tests can turn it on/off.
- R265 Bench: the opt-in latency bench (R257) records release-to-insert ms with the setting off ("before") and
  on ("after") and the WER of the tail-joined final transcript against the full re-transcription per WAV in
  build/latency.json.

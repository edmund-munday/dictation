# Requirements

- R266 Switched field: hold in field A, release, and before the insert happens focus moves to a different
  editable field B (different pid, or same pid with a different element id). Pass (Mac, HoldPipeline +
  InsertionCoordinator with the real Session, focus provider that reports B at insert time): the inserter is
  not called, no Return is sent even with auto-send on for that app, the panel is visible with text
  "Not inserted: you switched to a different field. Copy it instead." (`MenuMessages.insertSwitchedField`) and a
  Copy button; `session.panel.copyText` is the cleaned text and tapping Copy puts it on the pasteboard;
  `outcomes[index] == (false, false)`.
- R267 Same field: focus at insert time is A (same pid and element id; role label/frame may differ). Pass:
  inserted into A exactly as today, auto-send as today.
- R268 Nothing focused at insert time (focus provider reports no editable field / role .none): behaviour is
  exactly today's (same inserter calls, panel and outcomes as on main for that case). Pass: compared against
  the current behaviour with the same inputs.
- R269 Focus moved during the hold and back to A before insert: inserted into A. Focus in B at release but A
  again at insert: inserted into A.
- R270 Wiring: `InsertionCoordinator(session:inserter:pasteboard:focus:)` takes an optional `FocusProvider`
  (nil = today's behaviour, no check); the app passes its AX focus provider. The switched-field outcome is
  reported to the session through a public Session API so the panel/overlay/copyText come from Core.
- R271 Real sample: replaying Tests/Fixtures/audio/short-dictation.wav through HoldPipeline with real
  whisper-cli (skip only if whisper is not installed) and switching focus between release and insert yields the
  R266 outcome with the transcribed text behind Copy.

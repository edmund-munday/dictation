# 02 — Requirements: always-on dictation (v1)

Each item is one observable behaviour. **Pass** = the stated behaviour happens. **Fail** = anything else.
**Src:** CHG = requirements change 2026-10-13 (hold-to-talk), B = brief, D# = Edmund's decision #, T = design-think.md section (adopted).
**Test:** L = Linux, pure logic driven through the core's public API (`Session` events in, observable outputs out: inserted text, menu/overlay text, mic state), with a fake clock and scripted recognizer tokens. M = Mac only (real audio / AX / permissions / hotkeys): automated XCUITest/AX harness on the Mac, or a scripted manual checklist where automation is impossible (marked M*).

Shorthand: "inserts nothing" = the focused field's value is byte-identical before and after.

## A. Latch, menu bar, hotkey
| ID | Requirement | Src | Test |
|---|---|---|---|
| R1 | A menu-bar item is present whenever the app runs. | T Latch | M |
| R2 | Enabling (menu or Ctrl-Opt-Space) arms the tool; the mic stays closed until the talk key is held; the menu reads "Dictation is ready. Hold left Command in a text field to talk." | D12, CHG, CHG (left Cmd 2026-10-13) | L |
| R3 | Choosing Off closes the mic, wipes all buffered audio, and the menu reads "Dictation is off. The microphone is closed." | T, B | L, M |
| R4 | Ctrl-Opt-Space toggles On↔Off from any app. | D12 | M |
| R5 | The Ctrl-Opt-Space keystroke is never inserted into the focused field. | T | M |
| R6 | The hotkey can be changed in setup; the new chord toggles and the old one no longer does. | T | M |
| R7 | On first launch and after relaunch or crash, the app starts Off; it never reopens the mic until the user latches On. | T | L, M |
| R8 | If the mic is still open 300 ms after Off, the state becomes Fault: the menu reads "Dictation is off. The microphone is closed." plus a fault reason, and nothing is inserted until the user latches On again. | T | L (fake clock/device) |
| R9 | While the talk key is held over a focused editable field, the menu reads "Dictation is listening." | CHG | L |
| R10 | While mic permission is denied and the latch is On, the menu reads "Dictation is on but the microphone is blocked. Nothing is listening." and nothing is inserted. | T, D13 | L, M |
| R11 | There is no idle auto-off: after 8 h On with no speech, the latch is still On. | T | L (fake clock) |
| R12 | Keyboard and mouse keep working normally in every state. | B | M* |

## B. Modes
| ID | Requirement | Src | Test |
|---|---|---|---|
| R13 | ~~Flow is the default mode: a qualifying utterance is inserted with no key held.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R14 | Holding the talk key (Command, see R120–R122) while enabled starts capture; releasing it ends the utterance. The talk key does nothing while disabled. | CHG, D12 | L, M (talk key) |
| R15 | ~~In Guarded mode, speech that began up to 400 ms before the talk key went down is included.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R16 | ~~In Guarded mode, releasing Fn before the endpoint discards the utterance (nothing inserted, overlay cleared).~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R17 | ~~The mode setting persists across relaunch.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |

## C. What gets admitted (non-dictation speech)
| ID | Requirement | Src | Test |
|---|---|---|---|
| R18 | Speech while the talk key is not held inserts nothing and is not captured. | CHG | L |
| R19 | ~~Speech whose onset is within 400 ms before a field gains focus is inserted into that field in full.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R20 | ~~Speech whose onset is more than 400 ms before focus is dropped in full, including the part spoken after focus.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R21 | Secure text fields (passwords) and system secure input never receive text, and the menu reads "Dictation skips secure fields." | T | L (role), M |
| R22 | The tool's own windows and overlay never receive text. | T | M |
| R23 | While a call app (FaceTime, Zoom meeting, Teams meeting, Webex meeting) is frontmost, nothing is inserted (its chat field included) and the menu reads "On — paused for a call". | D9, T | L (frontmost-app input), M |
| R24 | While another app holds audio input on the default device, the mic is released and the menu reads "Dictation is paused while the other app has the microphone." | D9, T | L, M |
| R25 | When the call app stops being frontmost or the other app releases the mic, and the latch is still On, listening resumes without user action; speech from the paused gap is never inserted. | T | L, M |
| R26 | While hardware mute is on, nothing is inserted and the menu reads "Dictation is paused while the microphone is muted." | T | L, M* |
| R27 | 60 s of silence, fan noise or room noise inserts zero characters (including recognizer hallucinations like "Thanks for watching" during non-speech). | T | L (VAD-flagged frames), M (recorded noise) |
| R28 | An utterance consisting only of "uh", "um", "hmm", "ugh", "oh" or "ah" inserts nothing. | T | L |
| R29 | A sentence that starts with a mutter word is inserted (cleaned per section F). | T | L |
| R30 | On the built-in mic, ambient-level sound (at the 2 s noise floor) inserts nothing; on a headset, frames under 12 dB above the floor are dropped. | T | L (energy values), M |
| R31 | ~~The first time the built-in mic is used, the menu shows once: "This microphone hears the room. Nearby voices can land in the focused field. A headset, or Guarded mode, narrows that."~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R32 | ~~When a voiceprint exists, an utterance from a clearly different speaker inserts nothing.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R33 | Screen lock, sleep or lid close closes the mic and wipes buffers; nothing spoken during that time is ever inserted. | T | L, M |
| R34 | After unlock or wake with the latch On, listening resumes with an empty buffer, without re-toggling. | T | L, M |
| R35 | Switching audio route (e.g. to AirPods) mid-utterance inserts nothing from that utterance. | T | L, M |

## D. Insertion into the field
| ID | Requirement | Src | Test |
|---|---|---|---|
| R36 | A qualifying utterance is inserted at the caret of the focused editable field. | B | L (insert request), M (real apps) |
| R37 | Each utterance is inserted in one write and one undo step: Cmd-Z removes exactly that phrase. | T | M |
| R38 | Text before and after the caret is unchanged by an insert. | T | M |
| R39 | A selection of 80 characters or fewer with no line break is replaced by the inserted text. | T | L, M |
| R40 | With a longer selection, or one containing a line break, nothing is inserted, the selection stays, and the overlay says "Selection kept. Click where the words should go." | T | L, M |
| R41 | After an insert, the caret sits at the end of the inserted text with no selection. | T | M |
| R42 | Return, Tab, Escape or any shortcut is never sent to the field, including in terminals. | D6 | L (no key events emitted), M |
| R43 | In single-line fields, terminals and combo boxes, newline characters are removed from the inserted text. | T, D6 | L |
| R44 | Works in native text fields, browsers (Safari, Chrome, Electron apps) and terminals (Terminal, iTerm2). | D6 | M |
| R45 | If focus changes to another field or app before commit, nothing is inserted anywhere. | T | L, M |
| R46 | If insertion fails, the overlay shows "Heard you. Could not type into this field." with a Copy button that copies the text. | T | L (message), M |
| R47 | The user's clipboard is never changed by insertion. | T | M |
| R48 | Partial (uncommitted) words never appear in the field. | T, D4 | L, M |
| R49 | The floating panel appears only while the talk key is held and while cleanup runs, plus for failure messages; it is hidden otherwise. | CHG, D4 | L |
| R50 | When newlines were stripped, the overlay says "Newline stays out of this field." | T | L |

## E. Timing (fake clock on Linux; latency measured on Mac)
| ID | Requirement | Src | Test |
|---|---|---|---|
| R51 | ~~The insert happens no earlier than 400 ms of silence + 500 ms hold after the last speech.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R52 | When the LLM answers within its timeout, the insert happens within 100 ms of the LLM result; with the local fallback, within 200 ms of release. | CHG | L (fake clock), M (measured) |
| R53 | ~~A pause under 400 ms does not split an utterance into two inserts.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R54 | ~~A self-correction cue ("actually", "I mean", "no wait"…) at the end of speech extends the silence wait, so "friday… actually monday" is one insert.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R55 | ~~A cleanup result (local or CLI) arriving after the hold is ignored; the local result inserts on time.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R56 | ~~Escape during the wait discards the pending phrase; nothing is inserted.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R57 | ~~Typing a character during the wait discards the pending phrase and the typed character reaches the field.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R58 | ~~Without Input Monitoring permission, the menu adds "Typing will not cancel a pending phrase."~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R59 | ~~An utterance reaching 30 s of speech is cut at 30 s and inserted normally; the rest is a new utterance.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |
| R60 | ~~(If an overlay preview is shown) first partial words appear within 400 ms of speech onset.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on. | — | — |

## F. Cleanup, self-correction, punctuation (all L)
After the 2026-10-13 change, R61–R78 define the **local rule-based fallback** output (used when the LLM is Off, fails, times out or is rejected). The LLM path is defined by R80 and R111–R114.
| ID | Requirement | Src | Test |
|---|---|---|---|
| R61 | Local fallback cleanup: "ship it friday, actually I mean monday" → "Ship it Monday." | B, CHG | L |
| R62 | "that's actually fine" keeps "actually" (punctuated only). | T | L |
| R63 | "I actually think tuesday" keeps "actually". | T | L |
| R64 | "good, I mean really good" keeps both (no meaning change on ambiguity). | T | L |
| R65 | "don't send" keeps the negation. | T | L |
| R66 | "don't send, I mean do send" → "Do send." | T | L |
| R67 | Cues "scratch that", "no wait", "wait", "sorry", "I mean", "actually I mean", "no I mean" followed by a short replacement replace only the last matching item (weekday, number, name, or ≤4 words), not the whole sentence. | T, B | L (one test per cue) |
| R68 | "Scratch that" followed by a clause inside one utterance replaces that utterance's text before the cue with the clause. | B, T, D11 | L |
| R69 | ~~"Scratch that" (or any cue) alone never deletes or changes previously inserted text.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on (no post-insert span exists). | — | — |
| R70 | Local fallback cleanup never adds a word not spoken; only punctuation and capitalisation are added. (The LLM path may add light grammar words.) | B, CHG | L |
| R71 | Local fallback cleanup never removes a word except cues, fillers and the retracted words they license. | B, CHG | L |
| R72 | Negation words are never dropped unless inside the replaced part and the replacement carries the flip. | T | L |
| R73 | When a correction parse is ambiguous, the literal words are inserted (punctuated). | T | L |
| R74 | Output is auto-punctuated: sentence-final full stops/question marks and commas where clear, first word capitalised. | D10 | L |
| R75 | Spoken punctuation words stay words: "comma", "period", "new paragraph" appear as those words. | D10 | L |
| R76 | Filler mutters inside a sentence ("um", "uh") are removed. | B, D3 | L |
| R77 | The pronoun "I" and sentence starts are capitalised; other casing is from the recognizer. | D10 | L |
| R78 | Consecutive inserts into one field get correct spacing: a space before a new phrase when the caret follows a non-space character, none at start of field. | B | L (given preceding char), M |
| R79 | Cleanup is applied automatically to every utterance on release, no user action needed. | D3, CHG | L |
| R80 | On release, the whole raw transcript of the utterance is sent once to the configured LLM backend and its cleaned result is inserted (see R111–R114). | CHG | L (fake CLI) |
| R81 | If the CLI is missing or exits non-zero, the local fallback result is inserted and the menu notes "CLI cleanup unavailable; using local cleanup." once per session. | D2, D13 | L |
| R82 | Non-English speech is not translated or guessed; if the recognizer reports low confidence/other language, nothing is inserted. | D1 | L (scripted recognizer output) |

## G. Voice learning
| ID | Requirement | Src | Test |
|---|---|---|---|
| R83 | Setup offers voice enrollment; completing it enables on-device voice adaptation (profile version increments). | D8, CHG | L, M |
| R84 | Enrollment can be skipped; the tool works without it. | D8 | L |
| R85 | The voice profile improves from his accepted (not undone/cancelled) utterances; cancelled phrases are not learned from. | D8 | L (observable: accept count/profile version) |
| R86 | Voice data never leaves the machine and is never sent to a CLI. | D8, B | L (fake CLI receives text only), M (network check) |
| R87 | Settings has "Reset voice profile", which deletes it; speaker filtering then turns off. | D8 | L |

## H. Privacy and CLI egress
| ID | Requirement | Src | Test |
|---|---|---|---|
| R88 | No audio file is ever written. | B, D7 | L (fs watch), M |
| R89 | No transcript log is written. (REPLACED by R228 for the tuning corpus) | T | L, M |
| R90 | Audio is never sent to Cursor CLI or Claude CLI; only the phrase text is. | D2 | L |
| R91 | ~~Before the first CLI use, the app shows: "Sending the transcript to <Cursor CLI/Claude CLI> leaves this Mac. Audio stays here." and the CLI is used only after the user confirms.~~ **REMOVED**: requirements change 2026-10-13: hold-to-talk replaces always-on; Edmund approved CLI use, no consent prompt. | — | — |
| R92 | The CLI backend can be turned off in Settings; then no CLI process is started. | D2 | L |
| R93 | Text from secure fields or during calls is never sent to a CLI. | T, D9 | L |
| R94 | Pre-roll audio is at most 1.5 s, held in memory only, wiped on Off, lock, sleep, secure-field entry and commit. | D7 | L (public buffer-status API), M* |

## I. Setup and locked-down machine
| ID | Requirement | Src | Test |
|---|---|---|---|
| R95 | First-run setup lists each needed permission (Microphone, Accessibility, Input Monitoring) with its status and a button to open the right System Settings pane. | D13 | M |
| R96 | Missing Accessibility: the menu reads "Dictation can't type: Accessibility permission is missing." and nothing is inserted. | D13 | L, M |
| R97 | Missing Input Monitoring: the talk key cannot be detected, nothing is captured, and the menu reads "Dictation needs Input Monitoring to detect the talk key." | D13, CHG | L, M |
| R98 | If no on-device recognizer is available, setup stops with "This Mac has no on-device recognizer. Dictation needs one. Cloud speech is not used." and the app stays Off. | D13, B | L, M |
| R99 | The system speech recognizer is used only when it reports on-device mode; it never falls back to a server. | B, D13 | L (fake recognizer flag), M |
| R100 | If the bundled model can't be loaded (blocked download/install), the app falls back to on-device system speech and says "Using macOS on-device speech (bundled model unavailable)." | D13 | L |
| R101 | Permission revoked while running: the mic closes, the state goes to Refused/Fault with the matching message, and it never silently reopens. | T, D13 | L, M |
| R102 | The app can be distributed signed and notarized, runs without admin rights, and needs no background daemon beyond itself. | D13 | M* (release checklist) |
| R103 | The app makes no network connections in normal operation (CLIs aside, which are separate processes after consent). | B | M (network monitor) |

## J. Hold-to-talk and LLM cleanup (requirements change 2026-10-13)
| ID | Requirement | Src | Test |
|---|---|---|---|
| R104 | Holding the talk key while enabled opens the mic and shows the floating panel with "Listening…". | CHG | L, M |
| R105 | While the talk key is held, the panel shows the semi-live transcript, updated each time new partial words arrive. | CHG | L, M |
| R106 | On talk-key release the panel shows "Cleaning up…" until the text is inserted or a failure message replaces it, then hides. | CHG | L |
| R107 | The cleaned text is inserted into the field that was focused when the talk key went down, even if focus moved during the hold. If that field no longer exists, nothing is inserted and the Copy fallback (R46) is shown. | CHG | L, M |
| R108 | Holding the talk key with no editable field focused: on release nothing is inserted and the panel shows "No text field was focused." with a Copy button for the cleaned text. | CHG | L |
| R109 | A hold under 300 ms, or a hold with no speech, inserts nothing, sends nothing to the LLM, and closes the panel. | CHG | L |
| R110 | Pressing Escape while holding the talk key cancels: nothing is inserted, nothing is sent to the LLM, the panel closes. | CHG | L |
| R111 | Exactly one LLM call is made per utterance, with the raw transcript only (no audio, no earlier utterances), passed on stdin. | CHG, D2 | L (fake CLI records input) |
| R112 | The LLM result is inserted after trimming surrounding whitespace and wrapping quotes. It is rejected (local fallback inserted instead) if empty, longer than 2× the raw transcript + 40 characters, or starting with a preamble such as "Here is"/"Sure". | CHG | L |
| R113 | If the LLM has not answered within 4 s of release, the local fallback result is inserted, a later LLM answer is ignored, and the menu notes "LLM cleanup timed out; used local cleanup." once per session. | CHG | L (fake CLI with delay) |
| R114 | Settings offers the cleanup backend: Cursor CLI, Claude CLI, grok CLI, a local model, or Off (local rules only); with Off no process is started. | CHG, D2 | L |
| R115 | A hold reaching 120 s stops capture and is processed as if released; the panel notes "Maximum length reached." | CHG | L |
| R116 | Holding the talk key during a call (R23/R24 conditions) or in a secure field inserts nothing, sends nothing to the LLM, and shows the matching pause/skip message. | CHG, D9 | L |
| R117 | While disabled, Command keeps its normal system function and the panel never appears. | CHG | M |
| R118 | The raw transcript and the LLM result are never written to disk by the tool. | CHG, B | L (fs watch) |
| R119 | Releasing the talk key after the latch is disabled mid-hold inserts nothing and closes the mic. | CHG | L |
| R120 | The talk key is left Command by default; Settings can change it to right Command or either Command key. | CHG (Cmd), CHG (left Cmd 2026-10-13) | L, M |
| R121 | Capture starts only when the talk key is held on its own; holding Command together with any other key or modifier already down does not start capture. | CHG (Cmd) | L, M |
| R122 | If any other key is pressed while the talk key is down, it reaches the app as a normal shortcut, any capture is cancelled, the panel closes, nothing is sent to the LLM and nothing is inserted. | CHG (Cmd) | L, M |
| R123 | Pressing and releasing the talk key alone never sends a key event or shortcut to the focused app beyond the bare Command press. | CHG (Cmd) | M |
| R306 | A transcript that is only an invented Whisper silence phrase (subtitle credits such as "Subs by www.zeoranger.co.uk", "Thanks for watching!", a lone "you") is dropped like a lone mutter: nothing is inserted and no Copy fallback is offered. Real sentences that merely contain those words are still inserted. | T | L |
| R307 | A hold whose audio has no meaningful speech (fewer than 120 ms of 20 ms frames louder than both -55 dBFS and 10 dB above the hold's own noise floor) is stopped before transcription: Whisper is not run, and nothing is cleaned up, matched as a command, inserted, offered for copying or auto-sent. Quiet but real speech still goes through. As a second layer, auto-send never presses Return for text that is empty, a lone mutter or a silence phrase (R306). | T | L |
| R308 | Local cleanup (Edmund, 2026-11-13: "It just can't be talking to an external LLM to do the cleanup ... it needs to be able to handle both scenarios really easily"): `"api": "openai"` in gateway.json sends cleanup to `<url>/v1/chat/completions` in the standard chat-completions format (Ollama, llama.cpp), with no key required and no Authorization header when the key is empty, and reads the reply from `choices[0].message.content`. A reply in any other shape falls back to local rules. | T | L |
| R309 | A gateway.json without `api` behaves exactly as before: gateway format, `<url>/v1/chat`, key required. | T | L |

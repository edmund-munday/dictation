# Mac app: main behaviours and risky edge cases (lighter TDD, 2026-10-14)

Source: Edmund's brief and requirements change 2026-10-13 (docs/requirements/dictation), plus his instruction of 2026-10-14 to build the menu-bar app. Core behaviour (state machine, cleanup, fallback, panel text) is covered by DictationCore tests; this list covers the Mac wiring.

## Talk key (event tap)
- M1 Left Command pressed and released on its own (no other key or modifier) starts and ends a hold in the core. Right Command alone does nothing by default.
- M2 Any other key, or another modifier, pressed while left Command is held cancels the hold; the key event still reaches the app (the tap never swallows it).
- M3 Left Command pressed while another key/modifier is already down does not start a hold.
- M4 The tap never swallows or synthesises Command events.

## Toggle
- M5 Ctrl-Opt-Space toggles enabled/disabled; the menu-bar icon and menu text reflect the state. While disabled, holding Command does nothing.

## Speech
- M6 While holding, mic audio is transcribed on-device (whisper.cpp via whisper-cli with a local model when present, else Apple's on-device SFSpeechRecognizer with requiresOnDeviceRecognition); partial text appears in the floating panel.
- M7 No audio or transcript is written to disk except whisper's transient chunk files, deleted immediately after use.

## Cleanup
- M8 The cleanup CLI is chosen automatically: the first of grok, claude, cursor-agent that is installed and answers a probe within the timeout; otherwise local rules. Choice is shown in the menu.
- M9 The CLI is invoked with a fixed cleanup prompt and the raw transcript; its output (validated by the core) is inserted. Timeout/failure uses the local fallback.

## Insertion
- M10 Text is inserted via Accessibility into the element focused when the hold began (set selected text / value), never pressing Return.
- M11 If insertion fails or the original field is gone, the panel shows the text with a Copy button.
- M12 Secure (password) fields are skipped: nothing captured or inserted.
- M13 During a call (mic in use by a known call app), holds are blocked with the core's pause message.

## Permissions
- M14 On launch the app reports which of Microphone, Accessibility, Input Monitoring (and Speech Recognition if Apple fallback) are missing, in the menu, and offers buttons opening the right System Settings pane. It never tries to grant them.

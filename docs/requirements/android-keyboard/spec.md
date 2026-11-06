# Dictation on Android: voice-first keyboard (spec)

Status: proposed, waiting for Edmund's approval. Nothing is built until he approves it.

## 1. What it is

A custom Android keyboard (an input method) for Edmund's Pixel 8a that brings the Mac dictation tool to the phone. In any app's text field he switches to this keyboard, taps the talk button, speaks, taps again, and cleaned-up text appears in the field: self-corrections applied, fillers removed, punctuated, in his own words.

Decisions Edmund made (6 Nov 2026):

| Topic | Decision |
|---|---|
| Processing | Speech to text on the phone; cleanup by a cloud model is allowed |
| Keyboard | Voice-first pad: big talk button, live transcript, backspace, space, enter, switch keyboard |
| Talk gesture | Tap to start, tap to stop |
| Phone | Pixel 8a (Tensor G3; no on-device Gemini Nano for third-party apps) |

What carries over from the Mac tool unchanged:

- The cleanup contract: one LLM call per utterance with the raw transcript only (R111), the reject rules (R112), the 4 s timeout with local fallback (R113), and the local rule-based fallback (R61-R78).
- Privacy: no audio file and no transcript log is written (R88, R89, R118); audio never leaves the phone (R90); secure fields and calls are never sent anywhere (R93, R116).
- Behaviour: English only (R82), never presses Enter on its own, short or silent takes insert nothing (R109), 120 s maximum (R115).

What changes on the phone:

- Tap to start and stop replaces hold-left-Command. There is no "any other key cancels" rule; a Cancel button does that job.
- Insertion goes through Android's own keyboard channel into the field the keyboard is attached to, so the Mac's accessibility insertion, focus tracking and Input Monitoring problems disappear.
- The cleanup model is called over HTTPS from the phone instead of through a local CLI.

## 2. How it works

```
Talk tap -> on-device speech recognizer (partial words shown live)
Stop tap -> raw transcript -> cloud cleanup (4 s) --ok--> insert cleaned text
                                         \--fail/timeout/rejected--> insert local cleanup
```

### 2.1 Parts

| Part | What it does | Notes |
|---|---|---|
| `DictationImeService` | Android `InputMethodService`; shows the pad, owns one dictation session at a time, inserts text through `InputConnection.commitText` | The keyboard itself |
| `SpeechCapture` | Wraps `SpeechRecognizer.createOnDeviceSpeechRecognizer` (en-AU), partial results on | Never uses the network recogniser |
| `CloudCleanup` | One HTTPS call to the cleanup model with the raw transcript; 4 s deadline | Claude API, Haiku-class model by default |
| `LocalCleanup` | Kotlin port of `DictationCore/Cleanup.swift` | Used whenever cloud cleanup is off, fails, times out or is rejected |
| `SetupActivity` | Enable keyboard, grant microphone, enter the API key, check the speech model is downloaded, run a test take | The only full-screen UI |

### 2.2 Speech to text on the Pixel 8a

Recommended: Android's on-device recogniser (`createOnDeviceSpeechRecognizer`, Android 12+), which is the same Google on-device speech engine that Gboard uses. It gives live partial words, needs no network, and costs nothing.

Things to prove in the first spike (phase 0), because they decide whether this works:

1. **Long takes.** The recogniser ends a session after a pause in speech. Tap-to-stop needs it to keep listening until Edmund taps. Use segmented sessions (`EXTRA_SEGMENTED_SESSION`, Android 13+) or restart on each end-of-speech and join the segments, with no words lost at the joins.
2. **Speed.** Final transcript within about 0.5 s of the stop tap.
3. **Accuracy on Edmund's voice** against the Mac tool on the same sentences.

Fallback if the spike fails: whisper.cpp (small English model) on the phone. It handles long takes cleanly but gives no live partial words and is slower on the Tensor G3, so it is only the fallback.

The Mac tool's voice enrolment (R83-R87) does not carry over; the on-device recogniser has no per-user adaptation API.

### 2.3 Cloud cleanup

- **Call.** One HTTPS request per take to the Claude API, with the same system prompt the Mac tool's LLM path uses and the raw transcript as the only user content. No audio, no earlier takes, no field contents.
- **Model.** A fast Haiku-class model by default, because the 4 s budget includes mobile network time. The model can be changed in settings.
- **Key.** The API key is entered once in setup and stored encrypted with Android Keystore. It is never logged or shown again.
- **Rejecting results.** Trim whitespace and wrapping quotes. Reject an empty result, one longer than 2x the raw transcript + 40 characters, or one starting with a preamble ("Here is", "Sure"). Insert local cleanup instead (R112).
- **Timeout.** If no answer arrives within 4 s of the stop tap, insert local cleanup and ignore the late answer (R113).
- **Offline.** With no network, skip the call and insert local cleanup straight away; the pad says "Offline: used local cleanup."
- **Off switch.** Cloud cleanup can be turned off in settings; then no network request is ever made.

Alternative considered: send the transcript to a relay on the Pro, which then calls the CLI tools as the Mac does. It keeps the key off the phone, but it fails whenever the Pro is unreachable and adds a hop to every take, so it is not recommended.

### 2.4 Local cleanup and shared tests

`LocalCleanup` is a straight Kotlin port of `Cleanup.swift`. To keep the two the same, the Swift test cases for R61-R78 are exported once to `Tests/fixtures/cleanup-cases.json` (input, expected output), and both the Swift tests and the Kotlin tests run against that file.

## 3. The pad

One row of controls under a transcript strip, about the height of a normal keyboard.

```
+--------------------------------------------------+
| "ship it friday actually I mean monday"           |  <- live transcript / status
+--------------------------------------------------+
|                                                    |
|                 (   TALK   )                       |  <- big round button
|                                                    |
+--------+--------+---------------+--------+--------+
| switch | cancel |     space     |   <x   | enter  |
+--------+--------+---------------+--------+--------+
```

### 3.1 States

| State | Transcript strip | Talk button | Other keys |
|---|---|---|---|
| Ready | "Tap to talk" | Mic icon | All work |
| Listening | Live partial words; elapsed time after 60 s | Stop icon, pulsing | Cancel shown; space, backspace and enter disabled |
| Cleaning up | "Cleaning up..." with the raw words greyed | Disabled, spinner | Cancel shown |
| Inserted | The inserted text for 2 s, then "Tap to talk" | Mic icon | All work |
| Blocked | The reason (see 4.3) | Disabled | All work |

### 3.2 Keys

- **Talk.** First tap starts listening; second tap stops and processes the take. Light haptic tick on each.
- **Cancel.** Shown only while listening or cleaning up. Discards the take: nothing inserted, nothing sent.
- **Space.** Inserts a space.
- **Backspace.** Deletes one character; holding repeats. A swipe left on backspace deletes the last word.
- **Enter.** Performs the field's own action (Send, Search, Go, Done or a new line), as the app asks. Dictation never presses it.
- **Switch.** Tap returns to the previous keyboard (normally Gboard), for typing passwords, emoji or fixing a word. Long-press opens the system keyboard picker.

### 3.3 Inserting text

- Text goes into whichever field the keyboard is attached to when the take finishes.
- If Edmund moves to a different field during a take, the take is cancelled and the pad says "Field changed: nothing inserted." This is the phone version of R107.
- Spacing follows R78: a space is added before the new text when the character before the cursor is not a space, and none at the start of a field.
- If the field cannot take the text, the pad shows the cleaned text with a Copy button (the R46 fallback).

## 4. Rules

### 4.1 Requirements

| ID | Requirement | Test |
|---|---|---|
| AK1 | The app installs as an Android keyboard that can be enabled in Settings and chosen with the system keyboard switcher. | Device |
| AK2 | Setup walks through enabling the keyboard, granting the microphone, entering the API key, and checking the en-AU on-device speech model, showing each item's status. | Device |
| AK3 | The pad matches section 3: transcript strip, talk button, and the switch, cancel, space, backspace and enter keys. | Device, screenshot |
| AK4 | Tapping Talk in Ready starts listening; tapping it again stops and processes the take. | Unit (state machine), device |
| AK5 | While listening, partial words appear in the transcript strip as they arrive. | Device |
| AK6 | Speech recognition runs only on the phone, through the on-device recogniser; the network recogniser is never used. | Unit (fake factory), device |
| AK7 | A take keeps listening through pauses until the stop tap or 120 s, with no words lost between recogniser segments. At 120 s it is processed as if stopped and the strip says "Maximum length reached." | Device, unit (segment join) |
| AK8 | A take under 300 ms or with no words inserts nothing and makes no network request (R109). | Unit |
| AK9 | Cancel while listening or cleaning up inserts nothing, makes no further request, and ignores any late answer. | Unit |
| AK10 | Each take makes at most one cleanup request, containing the raw transcript only: no audio, no earlier takes, no field contents (R111). | Unit (fake HTTP server records body) |
| AK11 | Cloud results are trimmed and rejected as in R112; a rejected result inserts local cleanup. | Unit |
| AK12 | No cloud answer within 4 s of the stop tap: local cleanup is inserted, the late answer is ignored, and the strip says "Cleanup timed out: used local cleanup." | Unit (fake server delay) |
| AK13 | With no network, local cleanup is inserted without trying the request, and the strip says "Offline: used local cleanup." | Unit, device (aeroplane mode) |
| AK14 | With cloud cleanup turned off, no network request is ever made. | Unit |
| AK15 | Local cleanup produces the same output as the Mac's `Cleanup.swift` for every shared case (R61-R78). | Unit (shared fixture) |
| AK16 | Text is inserted into the field attached when the take finishes, with R78 spacing. Moving to a different field during a take cancels it with "Field changed: nothing inserted." | Unit (fake InputConnection), device |
| AK17 | Dictation never sends Enter or performs the field's action; only the Enter key does. | Unit |
| AK18 | In password fields (any password input type), Talk is disabled and the strip says "Password field: switch keyboard to type." | Unit (EditorInfo cases) |
| AK19 | In fields marked incognito (`IME_FLAG_NO_PERSONALIZED_LEARNING`), takes use local cleanup only and make no network request. | Unit |
| AK20 | During a phone or VoIP call, Talk is disabled and the strip says "Paused during a call." | Unit (audio mode), device |
| AK21 | No audio file and no transcript or result log is written; the API key is never logged. | Unit (file watch), code review |
| AK22 | The API key is stored encrypted with Android Keystore and never shown after entry. | Device |
| AK23 | Microphone permission missing or revoked: Talk is disabled and the strip says "Microphone permission is off: open setup." with a button to setup. | Device |
| AK24 | The on-device en-AU speech model missing: Talk is disabled and the strip says "Speech model not downloaded: open setup." | Unit (fake availability), device |
| AK25 | Non-English or very low-confidence speech inserts nothing (R82). | Unit (scripted recogniser) |
| AK26 | The microphone is open only while listening, and closes on stop, cancel, keyboard hidden, screen off or field change. | Unit, device (mic indicator) |
| AK27 | From stop tap to text inserted takes under 2.5 s for a 10-second take on Wi-Fi, at the median over 20 takes. | Device (timing log, no transcript) |

### 4.2 Permissions

- `RECORD_AUDIO`: granted in setup, because a keyboard cannot show the permission prompt itself.
- `INTERNET`: only for cloud cleanup.
- Nothing else: no contacts, no storage, no accessibility service.

### 4.3 Blocked messages

| Condition | Strip text |
|---|---|
| Password field | "Password field: switch keyboard to type." |
| Call in progress | "Paused during a call." |
| No microphone permission | "Microphone permission is off: open setup." |
| Speech model not downloaded | "Speech model not downloaded: open setup." |

## 5. Build plan

The code goes in a new `android/` folder in this repository, so the Swift and Kotlin versions share the cleanup prompt and test cases. Android Studio isn't needed on the Air; builds run as cloud jobs, and the APK is sideloaded with `adb install` (no Play Store).

| Phase | Delivers | Done when |
|---|---|---|
| 0. Spike | Bare keyboard with a talk button and the on-device recogniser | On the Pixel 8a: a 60 s take with pauses keeps every word; final text within 0.5 s of stop |
| 1. Pad and local cleanup | Full pad, state machine, Kotlin `LocalCleanup`, shared fixture, insertion rules | AK1-AK9, AK15-AK18, AK20-AK26 pass |
| 2. Cloud cleanup | Claude API call, key storage, timeout and reject rules, offline path | AK10-AK14, AK19, AK21, AK22, AK27 pass |
| 3. Daily use | A week of use; fixes for whatever annoys | Edmund chooses it over Gboard voice typing for messages |

Each phase is one Codex job. The spike runs first because the long-take behaviour (AK7) is the main risk; if it fails, phase 1 uses whisper.cpp and AK5 drops to showing words only after each pause.

## 6. Cost and running

- Speech to text: free (on the phone).
- Cleanup: one short request per take. At a Haiku-class price, a few hundred takes a day is in the order of cents a day. The exact figure depends on the current model price, which is checked when phase 2 starts.
- Battery: the microphone and recogniser run only while listening.

## 7. Defaults chosen in this spec (changeable in settings)

- Cleanup model: Claude, Haiku-class, for speed inside the 4 s budget. Grok can be added as a second backend if Claude's cleanup is not good enough.
- Incognito fields (AK19): local cleanup only, because the app marked the field as private.

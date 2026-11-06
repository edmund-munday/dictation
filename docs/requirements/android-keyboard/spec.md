# Dictation on Android: voice-first keyboard (spec)

Status: proposed, waiting for Edmund's approval. Nothing is built until he approves it.

## 1. What it is

A custom Android keyboard for Edmund's Pixel 8a that brings the Mac dictation tool to the phone. In any app he switches to this keyboard, taps the talk button, speaks, and taps again. The cleaned-up text then lands in the field: self-corrections resolved, fillers gone, punctuated, in his own words. In chat apps the keyboard can also send the message, as the Mac does.

Decisions Edmund made (6 Nov 2026):

| Topic | Decision |
|---|---|
| Processing | Speech to text on the phone; cleanup by a cloud model is allowed |
| Keyboard | Voice-first pad: big talk button, live transcript, backspace, space, enter, switch keyboard |
| Talk gesture | Tap to start, tap to stop |
| Phone | Pixel 8a (Tensor G3; Gemini Nano is not available to third-party apps on it) |

### 1.1 What carries over from the Mac tool

| Mac behaviour (main, 85c55c0) | On the phone |
|---|---|
| Cleanup through the LLM gateway (`gateway.json`: Cloudflare worker, `deepseek/deepseek-flash`, 5 s timeout) with the shared `CleanupPrompt` | Same gateway, same model, same prompt, same 5 s timeout |
| Minimal cleanup rules: fillers, stutters, self-corrections, mishearings, false starts; emphasis words and swearing kept (R224) | Same, through the shared prompt |
| Spoken punctuation becomes marks; "new line" and "new paragraph"; numbered lists; spoken quote markup (R225) | Same; `SpokenMarkup` ported |
| Local rule-based fallback when the gateway fails, times out or is rejected | Kotlin port of `Cleanup.swift`, checked against shared test cases |
| Reject rules: empty, too long, or a preamble (R112) | Same |
| Auto-send in chat apps, blocked by "don't send" at the end (R222, R223) | Same rule, using Android chat app package names (section 3.4) |
| User dictionary as preferred spellings in the cleanup prompt | Same list, also used to bias the recogniser |
| Tuning corpus of text-only JSON lines, default on, never for secure fields (R228) | Same format, stored privately on the phone, exported on request |
| Field changes before insert: nothing inserted, Copy offered (focus guard) | Same |
| Media paused while dictating, resumed after (media pause) | Android's audio focus does this |
| Silence gate (R307), English only (R82), no audio ever written (R88) | Same |

### 1.2 What does not carry over

- **Voice-command plugins** (screenshot, volume, media, rewrite selection). They drive the Mac; the phone version is dictation only.
- **Hold-left-Command and the pause menu.** Tap to start and stop replaces the hold, and the keyboard is only active while Edmund has chosen it.
- **Incremental and tail cleanup for long takes.** They exist to cut latency on long Mac dictations. The phone starts without them, and phase 3 adds them only if long takes feel slow.

## 2. How it works

```
Talk tap -> on-device speech recogniser (partial words shown live)
Stop tap -> raw transcript -> quote markup -> gateway cleanup (5 s)
              --ok--> insert cleaned text -> auto-send if a chat app and no "don't send"
              --fail/timeout/rejected--> insert local cleanup (same send rule)
```

### 2.1 Parts

| Part | What it does |
|---|---|
| `DictationImeService` | The keyboard: an Android `InputMethodService` that shows the pad, runs one take at a time and inserts text through `InputConnection` |
| `SpeechCapture` | On-device speech recogniser (en-AU) with live partial words and dictionary biasing; never the network recogniser |
| `GatewayCleanup` | One HTTPS call to the same LLM gateway the Mac uses, with the shared prompt; 5 s deadline |
| `LocalCleanup` | Kotlin port of `Cleanup.swift`, `SpokenMarkup.swift` and `SendIntent.swift` |
| `Corpus` | Appends one text-only JSON line per take, in the Mac's R228 format, to app-private storage |
| `SetupActivity` | Enable the keyboard, grant the microphone, enter the gateway key, check the speech model, edit the dictionary, export the corpus, run a test take |

### 2.2 Speech to text on the Pixel 8a

Recommended: Android's on-device recogniser (`createOnDeviceSpeechRecognizer`), the on-device speech engine that Gboard voice typing uses. It shows words live, needs no network, costs nothing, and can be biased towards dictionary words (`EXTRA_BIASING_STRINGS`).

The Mac now uses whisper.cpp (`ggml-small.en`) for accuracy, so phase 0 compares the two on the phone before anything else is built:

1. **Long takes.** The Android recogniser ends a session after a pause in speech. Tap to stop needs it to keep listening until Edmund taps. It must use segmented sessions (`EXTRA_SEGMENTED_SESSION`) or restart and join segments, without losing words at the joins.
2. **Accuracy.** Word error rate on 20 of Edmund's own phrases, including dictionary words (Kazey, Grok Bot), compared with whisper.cpp `small.en` and `base.en` run on the phone.
3. **Speed.** Time from the stop tap to the final transcript.

Recommendation rule: use the Android recogniser unless whisper is clearly more accurate on his phrases and still produces a final transcript within 1.5 s of stopping a 10 s take. With whisper, the live strip shows words after each pause rather than as he speaks, and the R306 and R307 Whisper fixes come across too.

### 2.3 Gateway cleanup

- **One request per take.** It goes to the gateway URL with the shared `CleanupPrompt`, the dictionary as preferred spellings, and the tokenised raw transcript. It never includes audio, earlier takes or field contents.
- **Model.** `deepseek/deepseek-flash`, the Mac's current setting, so both devices clean up the same way. A Claude or Grok model can be set if the gateway offers it.
- **Key.** The gateway key is entered once in setup, stored encrypted with Android Keystore, and never logged or shown again.
- **Bad results.** Results are trimmed. An empty result, one over 2x the raw transcript plus 40 characters, or one that starts with a preamble is rejected, and local cleanup is used instead (R112).
- **Timeout.** No answer within 5 s of the stop tap means local cleanup is used and the late answer is ignored.
- **Offline.** With no network, the request is skipped and local cleanup is used straight away.
- **Off switch.** Gateway cleanup can be turned off in settings; then no network request is ever made.

### 2.4 Keeping phone and Mac the same

- The prompt text moves from `CleanupPrompt.swift` into `shared/cleanup-prompt.txt`. Swift and Kotlin both load that one file, so it cannot drift.
- The local-rule test cases (R61-R78, R222, R224, R225) are exported to `shared/cleanup-cases.json` (input and expected output), and the Swift and Kotlin tests both run against them.
- The dictionary on the phone starts as a copy of the Mac's `dictionary.txt` and is edited in setup. Syncing between the devices is out of scope for v1.

## 3. The pad

```
+--------------------------------------------------+
| ship it friday actually I mean monday             |  <- live transcript / status
+--------------------------------------------------+
|                                                    |
|                  (   TALK   )                      |  <- big round button
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
| Cleaning up | "Cleaning up..." over the raw words, greyed | Disabled, spinner | Cancel shown |
| Inserted | The inserted text for 2 s ("Sent" when auto-sent), then "Tap to talk" | Mic icon | All work |
| Blocked | The reason (section 4.3) | Disabled | All work |

### 3.2 Keys

- **Talk.** The first tap starts listening and the second stops and processes the take. Each tap gives a light haptic tick.
- **Cancel.** Shown only while listening or cleaning up. It throws the take away: nothing is inserted, sent or logged as inserted.
- **Space.** Inserts a space.
- **Backspace.** Deletes one character, and repeats while held. Swiping left on it deletes the last word.
- **Enter.** Performs the field's own action (Send, Search, Go, Done or a new line).
- **Switch.** A tap returns to the previous keyboard (normally Gboard) for passwords, emoji or fixing a word. A long press opens the system keyboard picker.

### 3.3 Inserting text

- The text goes into the field the keyboard is attached to.
- If Edmund moves to a different field during the take or the cleanup, nothing is inserted and the strip shows the cleaned text with a Copy button: "Not inserted: you switched fields."
- Spacing follows R78: a space goes before the new text when the character before the cursor is not a space, and none goes at the start of a field.
- Line breaks from "new line", "new paragraph" or numbered lists are inserted as text, never as Enter presses.

### 3.4 Auto-send in chat apps

This is the phone version of R222 and R223.

- **When it sends.** After a confirmed insert into a chat app, the keyboard sends the message by performing the field's Send action (`IME_ACTION_SEND`).
- **Chat apps.** Google Messages, WhatsApp, Signal, Telegram, Slack, Discord, Messenger and Teams, plus any extra package names added in settings.
- **When it never sends.**
  - The insert failed, the text is empty, or the take was cancelled.
  - "Don't send" was said at the end.
  - The field does not offer a Send action. Some apps, such as WhatsApp by default, send only from their own button. In those apps the text is inserted, the strip says "Inserted: tap Send", and phase 0 records which apps expose Send.
- **Switch.** "Auto-send in chat apps", default on, matching the Mac.

## 4. Rules

### 4.1 Requirements

| ID | Requirement | Test |
|---|---|---|
| AK1 | The app installs as an Android keyboard that can be enabled in Settings and chosen with the system keyboard switcher. | Device |
| AK2 | Setup walks through enabling the keyboard, granting the microphone, entering the gateway key, checking the en-AU on-device speech model, editing the dictionary and exporting the corpus. Each step shows its status. | Device |
| AK3 | The pad matches section 3: the transcript strip, the talk button, and the switch, cancel, space, backspace and enter keys. | Device, screenshot |
| AK4 | Tapping Talk in Ready starts listening; tapping it again stops and processes the take. | Unit (state machine), device |
| AK5 | While listening, partial words appear in the strip as they arrive (Android recogniser) or after each pause (whisper). | Device |
| AK6 | Speech recognition runs only on the phone; the network recogniser is never used. | Unit (fake factory), device |
| AK7 | A take keeps listening through pauses until the stop tap or 120 s, without losing words between recogniser segments. At 120 s it is processed as if stopped, and the strip says "Maximum length reached." | Device, unit (segment join) |
| AK8 | A take under 300 ms, or one without meaningful speech (R307 levels), inserts nothing and makes no network request. | Unit |
| AK9 | Cancel while listening or cleaning up inserts nothing, sends nothing, makes no further request and ignores any late answer. | Unit |
| AK10 | Each take makes at most one gateway request. It contains the shared prompt, the dictionary and the tokenised raw transcript, and never audio, earlier takes or field contents. | Unit (fake HTTP server records body) |
| AK11 | The gateway request uses the URL, model and timeout from setup; defaults are the Mac's `gateway.json` values. | Unit |
| AK12 | Gateway results are trimmed and rejected as in R112. A rejected result uses local cleanup. | Unit |
| AK13 | No gateway answer within the timeout means local cleanup is used and the late answer is ignored. The strip says "Cleanup timed out: used local cleanup." | Unit (fake server delay) |
| AK14 | With no network, local cleanup is used without trying the request, and the strip says "Offline: used local cleanup." | Unit, device (aeroplane mode) |
| AK15 | With gateway cleanup turned off, no network request is ever made. | Unit |
| AK16 | Local cleanup, spoken markup and don't-send detection give the same output as the Swift code for every case in `shared/cleanup-cases.json`. | Unit (shared fixture, both languages) |
| AK17 | Phone and Mac load the cleanup prompt from `shared/cleanup-prompt.txt`. | Unit (both languages) |
| AK18 | Text goes into the attached field with R78 spacing. A field change during the take or cleanup inserts nothing and offers Copy with "Not inserted: you switched fields." | Unit (fake InputConnection), device |
| AK19 | Auto-send follows section 3.4: it happens only after a confirmed, non-empty insert into a listed chat app whose field offers Send, and never after "don't send" at the end, a cancel or a failed insert. | Unit |
| AK20 | Outside auto-send, dictation never performs Enter or the field's action; line breaks are inserted as text. | Unit |
| AK21 | In password fields, Talk is disabled and the strip says "Password field: switch keyboard to type." Nothing from them is ever logged. | Unit (EditorInfo cases) |
| AK22 | In fields marked incognito (`IME_FLAG_NO_PERSONALIZED_LEARNING`), takes use local cleanup only, make no network request, never auto-send and are not logged. | Unit |
| AK23 | During a phone or VoIP call, Talk is disabled and the strip says "Paused during a call." | Unit (audio mode), device |
| AK24 | While listening, the keyboard holds transient audio focus, so playing media pauses and resumes afterwards. | Device |
| AK25 | No audio file is ever written. The corpus holds text only, in the R228 format with `app` set to the package name, and can be turned off in setup. The gateway key never appears in any log. | Unit (file watch), code review |
| AK26 | The gateway key is stored encrypted with Android Keystore and never shown after entry. | Device |
| AK27 | Microphone permission missing or revoked: Talk is disabled and the strip says "Microphone permission is off: open setup." | Device |
| AK28 | The en-AU on-device speech model missing: Talk is disabled and the strip says "Speech model not downloaded: open setup." | Unit (fake availability), device |
| AK29 | Non-English or very low-confidence speech inserts nothing (R82). | Unit (scripted recogniser) |
| AK30 | The microphone is open only while listening, and closes on stop, cancel, keyboard hidden, screen off or field change. | Unit, device (mic indicator) |
| AK31 | From the stop tap to inserted text takes under 2.5 s for a 10 s take on Wi-Fi, at the median over 20 takes. | Device (corpus latency field) |

### 4.2 Permissions

- `RECORD_AUDIO`: granted in setup, because a keyboard cannot show the permission prompt itself.
- `INTERNET`: only for gateway cleanup.
- Nothing else: no contacts, no shared storage, no accessibility service.

### 4.3 Blocked messages

| Condition | Strip text |
|---|---|
| Password field | "Password field: switch keyboard to type." |
| Call in progress | "Paused during a call." |
| No microphone permission | "Microphone permission is off: open setup." |
| Speech model not downloaded | "Speech model not downloaded: open setup." |

## 5. Build plan

The code goes in a new `android/` folder in this repository, next to the Swift package, so both share `shared/`. Builds run as Codex jobs, not on the Air. The APK is installed on the phone with `adb install`, without the Play Store.

| Phase | Delivers | Done when |
|---|---|---|
| 0. Spike | Bare keyboard with a talk button; Android recogniser and whisper.cpp side by side; list of chat apps that expose Send | On the Pixel 8a, a 60 s take with pauses keeps every word, and the recogniser choice is made by the rule in 2.2 |
| 1. Pad and local cleanup | Full pad, state machine, `shared/` prompt and cases, Kotlin `LocalCleanup`, insertion and field-change rules | AK1-AK9, AK16-AK18, AK20, AK21, AK23, AK24, AK27-AK30 pass |
| 2. Gateway, auto-send, corpus | Gateway call, key storage, timeout, reject and offline paths, auto-send, corpus and export | AK10-AK15, AK19, AK22, AK25, AK26, AK31 pass |
| 3. Daily use | A week of use; fixes from the corpus; incremental cleanup only if long takes feel slow | Edmund uses it instead of Gboard voice typing for messages |

Phase 0 runs first because long takes (AK7) and recogniser accuracy are the main risks.

## 6. Cost and running

- **Speech to text:** free, on the phone.
- **Cleanup:** one short gateway request per take, the same per-take cost as on the Mac.
- **Battery:** the microphone and recogniser run only while listening.

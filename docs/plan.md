# Plan (v1)

## Architecture and language
- **Core (`DictationCore`, Swift package, platform-neutral):** session state machine (latch, modes, admit gates, timing), cleanup/self-correction/punctuation grammar, CLI-backend arbitration, menu/overlay message text. Its inputs are events: recognizer tokens with timestamps, VAD/energy/speaker scores, focus snapshots, frontmost app, mic ownership, keys, clock ticks. Its outputs are insert requests, mic open/close, and menu/overlay text. No Apple frameworks, so it builds and tests on Linux (Swift 6 toolchain on the worker).
- **Mac shell (`DictationApp`, Swift/SwiftUI menu-bar app):** AVAudioEngine capture → Silero-style VAD → streaming ASR (WhisperKit/whisper.cpp streaming on Apple Silicon; `SFSpeechRecognizer` with `requiresOnDeviceRecognition` as the locked-down fallback). Speaker embedding on-device for voice learning. AX focus watcher plus insertion (one-shot marked text → AX selected-text replace → ≤200-char key burst). Call/mic-owner detection (Core Audio process input + frontmost app). CGEventTap hotkeys and Fn. Signed and notarized, no daemon.
- **Auto-punctuation:** a small local punctuation/casing model or a rule set in the core, inside the 500 ms hold. Local LLM (e.g. MLX small model) optional. Cursor/Claude CLI is an opt-in, asynchronous backing cleaner: used only if it returns inside the hold and passes the token rules.
- Why Swift: one language for the Mac shell and core, native AX/Audio APIs, notarizable, and a Linux toolchain for the core tests.

## Test harness
- **Linux (worker, primary CI):** `swift test` on `DictationCore` through its public `Session` API with a `FakeClock`, scripted recognizer/VAD/focus event streams, and a fake CLI executable (a shell script) for R80/R81/R90–R93. Property tests for R70–R72 over a phrase corpus. Covers about 75% of R-IDs (every one marked L).
- **Mac (240b44e3):** XCTest targets (`DictationMacTests`) driving the app's own handlers (no XCUITest, GUI automation or virtual devices, per the 2026-10-14 test policy). Audio for end-to-end and latency tests (R52, R27, R32, R60) is recorded WAV fixtures fed straight into the app's audio-input handler (the `AudioSource`/`HoldPipeline` path), replacing the earlier XCUITest + BlackHole virtual input plan. Insertion is checked through the Accessibility bridge on known fields. Permission and locked-down cases (R95–R103) run on a fresh macOS user or VM with permissions withheld; R12/R26/R102 use a scripted manual checklist (M*).
- Each test name carries its R-ID; a script checks that every R-ID has a test and every test has an R-ID.

## Mac-only parts
Audio capture, VAD on real audio, ASR, and speaker ID (R27, R30, R32 end-to-end); AX focus, secure-field detection, insertion, undo, caret and clipboard (R21, R22, R36–R47); call and mic-owner detection (R23–R26); hotkeys and Fn (R4–R6, R14); lock/sleep/route change (R33–R35); permissions, setup and notarization (R95–R103); measured latency (R52, R60).

## Order
1. Tests for L-items (cursor-agent on worker) → all fail → commit and push.
2. Core implementation until green.
3. Mac shell plus Mac tests on the MacBook Air.

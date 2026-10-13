# 01 — Understanding (after clarifying round 1, 2026-10-13, ticket tsk_22e1941c)

Sources: `00-brief.md` (Edmund's brief), `docs/design-think.md` (think design run), and Edmund's answers to 13 decisions.

## Edmund's decisions (paraphrased faithfully)
1. **Language:** English only.
2. **CLIs:** Cursor CLI and Claude CLI may be called (overrides think's "no"). They are a backing tool, kept out of the latency-critical insert path unless needed.
3. **Mode:** Flow is the default, with automatic fixing (cleanup/self-correction) applied as he goes.
4. **Overlay:** only if needed.
5. **Timing:** keep 400 ms endpoint silence, 500 ms repair hold, 1.2 s post-commit window.
6. **Targets:** terminals and browsers are in; never press Return.
7. **Buffers:** 1.5 s in-memory pre-roll ring and a 30 s per-utterance cap are OK.
8. **Voice:** yes, learn his voice and improve over time, on-device.
9. **Calls:** block dictation during calls.
10. **Punctuation:** spoken punctuation words ("comma", "new paragraph") stay as words; the tool auto-punctuates.
11. **Editing commands:** none in v1 (no "scratch that" as a command, no "delete that", no structural edits).
12. **Hotkeys:** Ctrl-Opt-Space toggles; Fn is the Guarded-mode hold key.
13. **Work laptop:** a MacBook Pro. Permissions, unsigned apps and on-device speech are unknown, so design for a locked-down machine: graceful degradation, clear setup failure messages, and a signed/notarizable path.

## Restated understanding
A menu-bar macOS app. When latched On it listens continuously and types what Edmund dictates into whatever editable, non-secure text field has focus, in any app including terminals and browsers. It never presses Return/Tab/Esc. It ignores speech that isn't dictation as far as the design can: no focused field, calls, noise, mutters, pre-focus speech, and voices that don't match his learned voiceprint. Each phrase is inserted once, after 400 ms of silence plus a 500 ms hold, as one undo step. Before insertion it is cleaned automatically: in-utterance self-corrections ("friday, actually I mean monday" → "monday") are resolved without changing meaning, and punctuation and capitalisation are added automatically. Spoken punctuation words are kept as words. Everything runs on the machine. Cursor/Claude CLI may be used as a backing cleanup tool, but the insert never waits on them beyond the hold; if they're late, the local result is used. No transcript log and no audio files. Voice learning data stays on-device. On a locked-down work Mac it degrades gracefully, telling the user exactly which permission or capability is missing.

## Interpretations made (flagged; see the questions in plan.md)
- "No editing commands in v1" removes standalone "scratch that"/"delete that" acting on already-inserted text. Self-correction cues *inside one utterance* ("scratch that, ship it monday" before commit) are still cleaned as self-corrections, since that is the brief's "fix what he says".
- "Auto-punctuate" overrides think's add-nothing rule for punctuation and capitalisation only. Word-level changes stay deletion-only (no new words).
- "Fixing as he goes" means cleanup is applied at commit, inside the 500 ms hold. No retroactive rewrite of committed text, since there are no editing commands in v1.

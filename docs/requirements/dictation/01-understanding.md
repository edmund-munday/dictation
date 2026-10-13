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

## Requirements change 2026-10-13: hold-to-talk replaces always-on
Edmund's new flow: he mouses into a field and holds Fn (Ctrl-Opt-Space enables/disables the tool). He talks freely, including mistakes and self-corrections, while a small floating panel shows a semi-live transcript. On release, the whole utterance goes to an LLM for **aggressive** cleanup that still sounds like him and keeps his meaning: self-corrections, fillers, false starts, punctuation, light grammar. The result is inserted into the field that was focused when he started holding.
Kept: English only, voice learning, never pressing Return, no audio/transcript logs, blocked during calls, password fields skipped, Copy fallback, locked-down work Mac support.
LLM backends: Cursor CLI, Claude CLI or grok CLI (approved), or a local model. Prefer local or the fastest CLI, with a local rule-based fallback on failure or timeout.
Obsolete: Flow/Guarded modes, voiceprint gating of bystanders, the 400 ms pre-focus rule, the endpoint/repair-hold timing, the 1.2 s lease, the CLI consent prompt.
My decisions on Edmund's behalf (he said I decide timeouts): LLM timeout 4 s after release; max hold 120 s; holds under 300 ms ignored; LLM result rejected if empty, over 2× raw + 40 characters, or starting with a preamble.
Update (same change): the hold key is **Command, not Fn**. Capture starts only when Command is held on its own. Any other key pressed while Command is down makes it a normal shortcut: capture is cancelled and nothing is inserted. Right Command was the default (superseded below: left Command is the default); either Command key is configurable. Release ends capture and triggers cleanup and insertion.

Update (Edmund, 2026-10-13, later): the default talk key is **left Command**, not right. Still configurable (right or either Command), still held alone, other-key cancel unchanged. Affects R2 (ready text) and R120 (default).

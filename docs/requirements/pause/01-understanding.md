# Pause — understanding

## What exists today (main 5ad89e7)
- The first menu item is `ToggleController.menuTitle`: "Dictation On (Ctrl-Opt-Space turns off)" / "Dictation Off (Ctrl-Opt-Space turns on)". Clicking it, or pressing Ctrl-Opt-Space, flips the Session latch.
- Latch off already blocks hold-to-talk: the mic does not open, no panel shows, and nothing is transcribed or inserted. Turning it off mid-hold cancels the hold and drops a pending insert (`Session.setLatch(.off)`).
- Icon: `mic.fill` when on, `mic.slash` when off. `AppModel` sets the latch on at every launch.
- Edmund didn't notice the item, so the gap is discoverability and visible state, not the mechanism.

## Decisions
- Wording: the item reads "Pause dictation (Ctrl-Opt-Space)" while active and "Resume dictation (Ctrl-Opt-Space)" while paused. It stays the first menu item.
- Paused icon: the SF Symbol `pause.circle`, distinct from the active `mic.fill`. (Default picked; easy to change.)
- Pause is the existing latch-off state, not a second flag, so the hold key, Ctrl-Opt-Space and the menu all agree.
- Not persisted: a launch always starts active (as today). No timed pause.
- Pausing mid-hold or while a result is pending: the hold is cancelled and nothing is inserted (existing latch-off behaviour, now covered by a test).
- Tests live at the handler level in `Tests/DictationMacTests` (ToggleController, Session, HoldPipeline input), as the existing M5 ToggleTests do. No UI automation.

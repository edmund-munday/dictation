# Pause — requirements

- **R289 Pause item.** While active, the first menu item reads "Pause dictation (Ctrl-Opt-Space)". Choosing it (or pressing Ctrl-Opt-Space) pauses, and the item then reads "Resume dictation (Ctrl-Opt-Space)". Choosing it again resumes. Fail: the old "Dictation On/Off" wording, or the item text not following the state.
- **R290 Paused icon.** While paused, the menu-bar icon is `pause.circle`; while active it is `mic.fill`. Fail: the paused icon equals the active icon, or the icon doesn't change back on resume.
- **R291 Paused holds do nothing.** While paused, holding and releasing left Command (fed through the hold pipeline's key input) opens no mic, shows no panel, transcribes nothing and inserts nothing. Pausing during a hold cancels that hold and inserts nothing. Fail: any capture, panel, transcript or insert while paused.
- **R292 Resume works.** After resuming, holding left Command dictates normally again: the mic opens and the panel shows. Fail: the talk key stays dead after resume.
- **R293 Not persisted.** A fresh launch starts active, whatever the state at quit. (Already true in `AppModel`; checked by review, no new test.)

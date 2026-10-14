# Requirements (Core decision logic; Mac glue thin)
Public API in DictationCore: `enum MediaPlayState { case playing, notPlaying, unknown }`, `protocol MediaController: AnyObject { func playState() -> MediaPlayState; func pause(); func resume() }`, `final class MediaPauseCoordinator(controller:enabled:)` with `var enabled`, `func dictationStarted()`, `func dictationEnded()`, and `static func isEnabled(in: UserDefaults) -> Bool` (key "pauseMediaWhileDictating", default true).
- R239 Dictation start with media playing and the setting on: pause() is sent exactly once; on end (release or cancel) resume() is sent exactly once.
- R240 Nothing playing, or state unknown: start sends no pause, end sends no resume (never starts paused media).
- R241 Resume only if we paused: a second end, or an end with no matching start, sends nothing; a new start while we already paused does not pause again or lose the resume; after resume a later dictation starts fresh.
- R242 Setting off: no state query, no pause, no resume. Turning the setting off mid-dictation after we paused still resumes on end (we never leave media paused). Default (unset) is on; stored false is off.
- R243 Mac glue: HoldPipeline reports capture start (mic actually opened) and capture end (release, or cancel by another key) to an optional observer, once each.

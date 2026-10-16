# Requirements

- R299 Enable result: cache a pid only when setting `AXManualAccessibility` returns `.success`
  or a permanent unsupported result (`.attributeUnsupported`, `.notImplemented`, `.actionUnsupported`).
  All other results are temporary and leave the pid uncached, including `.cannotComplete`,
  `.notEnoughPrecision`, `.failure`, and `.apiDisabled`, so a later enable attempts the set again.
- R300 One gated retry: in `currentFocus`, when the first focused-element lookup for the frontmost
  pid returns nil, that pid is not cached as unsupported, and it has not produced a focused element
  since its last enable, re-set `AXManualAccessibility` ignoring the enable cache, pause once for
  0.15 seconds through the pause seam, and look up focus once more. There is at most one re-enable,
  one pause, and one retry per call; never loop. Once a pid produces focus, later nil lookups cost
  no re-enable or pause until another enable. Native apps that report unsupported (including a
  newly attempted enable), and the empty desktop/Finder, never pause.
- R301 No added latency: if the first lookup finds an element, return it without pausing, setting
  `AXManualAccessibility`, or looking up focus again.
- R302 Fallback unchanged: if the retry also returns nil, `currentFocus` returns the existing
  snapshot with role `.none` and identity `.none`. The existing R238 not-inserted panel with Copy
  appears exactly once. Do not change Session, Core, or the panel.
- R303 Logging: through the log seam, emit one `NSLog` line per pid per `AXError` code, for example
  `Dictation AX: AXManualAccessibility pid 123 com.anthropic.claudefordesktop err -25204`.
  Never repeat the same pid/code line during that process lifetime and never log dictated text.
- R304 Thread safety and cleanup: guard `manualAccessibilityPIDs` and all per-pid retry/logging state
  with an `NSLock`, since activation notifications run on main and `currentFocus` runs on AppModel's
  work queue. Remove a pid and all of its state on `NSWorkspace.didTerminateApplicationNotification`
  so a relaunched process, including a reused pid, starts fresh.

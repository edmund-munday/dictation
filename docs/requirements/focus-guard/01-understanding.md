# Understanding

Today the session records the focused field at talk-key down (`focusAtDown`, R107) and the insert request
targets it. `InsertionCoordinator.poll` (DictationMac) later inserts, after whisper and the gateway reply
(often 1-4 s after release). AX insertion writes to the remembered element, but Chromium/Electron fields use
paste (Cmd-V, R219), which lands in whatever is focused *now*: if Edmund has clicked into another field
meanwhile, the text goes there and auto-send may press Return there.

Change: at the moment of insertion, read the current focus. Compare identities by pid + AX element identity
(`FocusIdentity.pid` and `elementID`; the element id is stable per AX element via CFEqual). Frame/role labels
are not compared (a text area can grow while typing).
- Current focus is an editable field and is a different field than the request target: no insert, no Return,
  the panel stays visible with "Not inserted: you switched to a different field. Copy it instead." and the
  working Copy button holding the text; the overlay shows the same; corpus outcome inserted=false,
  autoSent=false.
- Same field: insert as today (auto-send as today).
- Nothing focused / no editable field focused at insert time: today's behaviour, unchanged.
This supersedes the part of R107 that inserted into the hold-start field even when another field has focus at
insert time. Focus moving during the hold and coming back before insert is fine (same field at insert time).

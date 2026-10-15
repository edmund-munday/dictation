# Brief (Edmund, 15 Oct 2026 3:09 PM Melbourne, via Tool Builder; ticket tsk_7a395600)

Bug: if Edmund releases the key and then clicks into a different text field before the text is ready, the text gets inserted into the wrong field.

Fix: when recording starts, record which field has focus (the AX focused element identity plus the app or pid). At insert time, compare it with the field that now has focus. If they differ, don't insert and don't auto-press Enter. Behave like the no-field-focused case (panel stays with the working Copy button), but show a clear message in the panel, e.g. "Not inserted: you switched to a different field. Copy it instead." If nothing is focused at all, keep today's no-field behaviour. Same field means insert as today.

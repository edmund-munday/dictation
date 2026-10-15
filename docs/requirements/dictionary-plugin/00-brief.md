# Brief (Edmund, 15 Oct 2026 3:45 PM Melbourne, via Tool Builder; ticket tsk_3673330b)

Custom dictionary plugin with voice entry by spelling.
- Trigger "add word" followed by spelled letters, e.g. "add word K A Z E Y". Handle whisper's variants: single letters, letters with commas or hyphens, "capital K", "double s", and "space" for multi-word terms.
- It assembles the term and appends it, deduplicated, to a user dictionary file in ~/Library/Application Support/Dictation/ (e.g. dictionary.txt, one term per line). Migrate the current whisperPrompt vocabulary (Kazey, script, Snip) into it.
- The panel confirms with "Added: Kazey" and no text is inserted.
- "remove word <spelled>" removes a term. A menu item opens the file.
- Every dictation feeds the dictionary into whisper's prompt or vocabulary hint (watch the prompt-length limit; the most recent terms win if truncated) and into the gateway cleanup prompt as preferred spellings.
- Use the existing plugin framework, preferably with an executable script per Edmund's preference, and the exact-phrase fast path so there's no gateway call. Dictation is exempt from the no-regex rule, so letter parsing can be deterministic.

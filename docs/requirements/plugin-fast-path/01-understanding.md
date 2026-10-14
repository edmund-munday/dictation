# Understanding (defaults chosen, no open questions)
- Field name: `confirm_delay_s` (number, seconds, default 1.5, clamped to 0...10).
- Leading fillers stripped: um, umm, uh, uhh, er, erm, ah, hmm, so, okay, ok, well, hey (repeated, any order). Only at the start.
- "Unambiguous" = exactly one plugin matches at the most specific template length; a tie between different plugins falls through to the gateway.
- Fast path never runs in secure fields (same as R232). It uses the same enabled/required-arg rules as R230.
- confirm_delay_s 0 = the command is handed to the runner at once (no "Running" wait); any delay > 0 keeps the cancel behaviour.
- Bundled echo and screenshot defaults get confirm_delay_s 0; the user's existing ~/Library/.../screenshot.json and echo.json are edited by hand; bin/screenshot.sh left alone.

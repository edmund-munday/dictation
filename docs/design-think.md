While the latch is On, the microphone stays open and a 1500 ms RAM ring keeps the onset of a phrase. A text field changes only when every admit check below passes, speech has been quiet for 400 ms, and a further 500 ms repair hold has elapsed. The write is one plain-text string, at the caret or a short selection, in one undo group. Until that write, the field’s value stays as the user left it. Partials are drawn on a non-activating overlay. The overlay is never a text target.

Capture, admit, write, and retain are four different permissions. On is permission to capture. Admit decides whether this utterance may become a string. Write decides whether that string may touch the caret. Retain decides whether anything may reach disk or a CLI. “Delay line” means only this: composition holds the finished string off the caret until the repair hold ends. Stages before the write can drop a phrase with no user-visible residue. The write names one element and one span.

Cloud speech is unused. Cursor CLI and Claude CLI are not ears and do not sit in front of the caret. They may see text only after a separate egress confirmation. Mouse and keyboard stay live in every state and can cancel a pending phrase or seal a span. A parallel writer at the caret is the keyboard replacement: one undo step, short selections replaced the way typing replaces them, the rest of the document unread.

The factory address mode is Flow, not Guarded and not a wake phrase. Flow commits when the admit checks pass and the hold ends. Guarded is in the same build for open offices: the mic is already open, and the phrase commits only if Fn is down at the endpoint. Onset may precede Fn by up to 400 ms. Releasing Fn discards the phrase, overlay included. Flow is factory because the brief is continuous listen as a keyboard replacement, including thinking pauses with no key down. Guarded as the only path is hold-to-talk. A wake phrase misses ordinary dictation and still hears the room. A warmth timer (auto-commit only after a recent key) treats a legal pause between sentences as self-talk and drops the next sentence. Self-talk in a focused field remains Flow’s residual hazard. Escape, a character key, and “scratch that” are the in-session answers. The user can switch their machine to Guarded.

Provisional words stay on the overlay. Marked text is used as a one-shot commit of the final string, not as a live underline of partials. Live underlined partials lose because chat send, autocomplete, and undo treat them as field text.

## Latch and states

One menu-bar item is always present. Its label is derived from whether the device is open. One global hotkey latches On and Off. Factory chord is ⌃⌥Space (Control-Option-Space). You can change it at setup. Until a chord is stored, On and Off are menu-only. The chord is consumed and is not inserted into the field. Doubt about the latch resolves to Off: mic closed, no write, no silent reopen after a crash or a relaunch. Hardware mute outranks the app.

There is no idle auto-off. The orange mic dot and the menu are the battery and privacy signal. An idle auto-off would punish continuous listen, so it is not in this version.

| State | Mic | Field | Menu |
|---|---|---|---|
| Off | Closed. Ring wiped. | Untouched | “Dictation is off. The microphone is closed.” |
| Refused | Closed. No waveform. | Untouched | “Dictation is on but the microphone is blocked. Nothing is listening.” |
| Listening | Open. 1500 ms ring only. | Untouched | “Dictation is listening. Click a text field to type.” |
| Ready | Open. Ring only. | Untouched | “Dictation is on. This field will receive speech.” Guarded: “Guarded — hold Fn to type into this field.” |
| Deaf | See the admit table. | Untouched | The reason line in that table. |
| Composing | Open. Phrase buffer holds the active utterance. | Untouched | Overlay partials, plus “Esc cancels”. |
| Holding | Open. Phrase buffer still held. | Untouched | Pending string on the overlay, plus “Esc cancels”. |
| Committed | Open. Phrase audio wiped. Token string kept for the lease. | One span written | Overlay dismisses. |
| Fault | Closed if the close succeeds. | Untouched | “Dictation is off. The microphone is closed.” plus the fault reason. Insert disarmed until the user latches On again. |

If the menu would say Off while the device is still open 300 ms after a close request, the state is Fault and insert is disarmed.

Escape during Composing or Holding drops the utterance, clears the overlay, and leaves the caret alone. A character key during Holding does the same and is delivered to the field. Input Monitoring is how those keys are seen in time. If that permission is missing, a pending phrase still seals on focus change and on the lease timer, and the menu adds “Typing will not cancel a pending phrase.”

## What gets admitted

The same mouth produces dictation, self-talk, and the user’s side of a call. Speaker diarization does not separate those three. Admit is a conjunction. Every check has to pass for this utterance. A miss discards the samples. Discarded speech is never flushed into a field that gains focus later.

A write happens only when all of the following are true together:

- The latch is On, microphone permission is granted, the recognizer is running, the focus watcher is alive, the screen is unlocked, the lid is open, and the Mac is awake.
- The focused role is a text field, text area, combo-box text, or editable web area. It is not a secure text field. Secure input is off. The tool’s own panels never qualify.
- Focus identity now equals focus identity at phrase acceptance. Identity is pid plus the element’s unique id, or pid plus role plus frame when no id exists. Two disagreeing focus reads mean Deaf until one reading is stable.
- No other app is running input on the default device. The frontmost window is not FaceTime, a Zoom meeting, a Teams meeting, or a Webex meeting. That app’s chat field is inside the veto.
- Hardware mute is off.
- Voice activity passed. A lone mutter did not. If the user has recorded a voiceprint, the segment is not a far mismatch.
- The mode is Flow, or the mode is Guarded and Fn is down at the endpoint.
- Endpoint silence has elapsed and the repair hold has elapsed.
- The string is the recognizer’s literal tokens, or a grammar result that passes the token rules below.

| Situation | Mic | Audio | Menu |
|---|---|---|---|
| Latch Off, Fault, Refused, lock, sleep, lid shut, permission loss, recognizer crash | Closed | Wiped | Off or Refused or Fault, as above |
| Another app owns the device, a call app is frontmost, or hardware mute | Released | Wiped | “Dictation is paused while the other app has the microphone.” Mute uses “Dictation is paused while the microphone is muted.” |
| No editable focus, or the focus watcher is dead | Open | Ring overwrites. No phrase buffer. | Listening line |
| Secure input, or a secure field | Open | Wiped on the entering edge. New samples discarded until it clears. | “Dictation skips secure fields.” |
| Call veto specifically | Released, same as another owner | Wiped | “On — paused for a call” |

When the other owner lets go, or the call app stops being frontmost, and the latch is still On and the screen is unlocked, the tool takes the mic back. Audio from the gap is not kept. Lock and sleep close the device even though the latch stays On. On unlock the session returns to Listening or Ready with an empty ring. Nothing from the locked interval exists to commit. Models may stay loaded across lock.

**Pre-roll.** The idle ring is 1500 ms (playtest band 1000–2000). It is RAM, overwritten in place, and it is the only audio kept while no phrase is accepted. A phrase may attach to a newly focused field only when its onset is inside 400 ms before that focus event (band 200–800). “You start the word as you click” stays one utterance. “A colleague talks, then you click Notes” inserts nothing: an onset older than the join window is dropped whole, tail included, so a hot mic cannot finish a sentence that was addressed to the room.

**Voice activity.** Speech frames are the only frames that enter the decoder. Decoder text whose time range contains no speech frames is dropped. 60 seconds of room noise, fan, or silence writes zero characters.

**Energy.** The noise floor is the ambient level over the previous 2 seconds. On a headset, speech frames must sit 12 dB above that floor. 12 dB is a playtest seed, not a measured constant for every room. On the built-in mic, frames at that floor are dropped, which catches a far television and a fan. A person at the next desk still passes. Built-in mics are allowed. The first time one is used, the menu shows once: “This microphone hears the room. Nearby voices can land in the focused field. A headset, or Guarded mode, narrows that.”

**Mutters.** An utterance that is only “uh”, “um”, “hmm”, “ugh”, “oh”, or “ah” does not commit. A lexical sentence that merely starts with one of those does.

**Enrollment.** This version ships with no voiceprint. After the user records one, a far mismatch is one more discard. Until that recording exists, the product does not pretend the laptop array can reject a nearby person. A voiceprint still admits the user’s own self-talk.

**Phrase buffer.** Once a phrase is accepted, Apple Silicon keeps that phrase’s audio in RAM so an optional second pass can run inside the hold. The cap is 30 seconds of speech-active audio, then a forced endpoint. The work profile has no second pass: it keeps the 1500 ms ring and the token string, and it drops phrase audio once the tokens exist. Neither profile writes a file. The 30 second cap is a safety limit you did not ask for. It is what ships so one undo group and one RAM phrase stay bounded. You can move it inside 20–45 seconds or remove it. Removing it means one monologue can sit in RAM until the next 400 ms pause.

A route change, including a flip to AirPods, resets the decoder, aborts the composing utterance, and writes nothing from the partial.

## How text enters the field

Re-read the target at the moment of the write. On an identity mismatch, abort. The uncommitted buffer does not follow the new focus. Never set the whole field value. Never send Return, Tab, Escape, or a shortcut. A newline character inside the commit string is written as a character, via the accessibility selection, only in a text area or an editable web area. In a terminal, a single-line field, or a combo box, newlines are stripped and the overlay says “Newline stays out of this field.” The user presses Return themselves. A dictated `rm` therefore sits on the line until they do. Terminal and browser composers, including Electron, are in this version.

Selection behavior at commit:

- Empty selection: insert at the caret.
- A selection of at most 80 characters with no line break: replace it. That is the typing behavior for a short highlight.
- A longer selection, or one with a line break: write nothing, leave the highlight where it is, overlay “Selection kept. Click where the words should go.”

Collapsing a long selection and inserting anyway loses, because that is an edit the user did not speak, and a false commit would destroy the highlight’s target. Replacing any selection regardless of size loses for the same reason on a highlighted paragraph.

Channel, probed once per app and cached. One channel per commit, so a marked-text commit and an accessibility commit cannot both fire.

1. One-shot marked text, when this tool is the active input source and the probe says the app accepts it. The final string is set as marked text and committed in the same turn. The field does not show partials during Composing or Holding.
2. Accessibility replacement of the selected range only. Caret ends after the new span. One undo group when the app allows it.
3. A single burst of character events, only for a string of 200 characters or fewer, only after a fresh focus check, never including Return, Tab, or Escape.
4. On failure, the overlay keeps the sentence and offers Copy. “Heard you. Could not type into this field.”

Automatic clipboard injection is off on both profiles. The work profile does not offer the setting. The personal profile can turn it on later: copy the pasteboard aside, paste, restore, and if the pasteboard changes during the gesture, abort and leave the user’s clipboard. It is off because the gesture races a copy the user made during the phrase, clipboard managers, and work DLP. The Copy button leaves the paste to the user.

After a successful write, the caret sits at the end of the span and the selection is collapsed. No extra key is sent to dismiss the app’s autocomplete.

The owned span is pid, element, range, and the exact string written. “Scratch that” and any later repair re-read that range. If the live characters differ, or accessibility cannot read them back, ownership releases and the document is left alone. The overlay says “Press undo to remove that phrase.” The tool does not send a counted burst of backspaces. Hand-typed text is outside the span. Deictic edits (“the second paragraph”) need the document and are out of this version. Chrome, Electron, and Terminal often misreport accessibility. The write path uses the string it just produced. It does not read the document to decide what the user meant.

## Clocks

The user sees partials early. The field changes once. Streaming local recognition is the hot path. A batch recognizer that waits for the end of the utterance misses the partial budget and is not a listener. A machine whose only recognizer is batch stays Off.

| Clock | Ships at | Band | On a miss |
|---|---|---|---|
| First overlay partial | 300 ms from voice-activity onset | 200–400 ms | Overlay stays empty. The caret stays put. No guessed words. |
| Prefix stability | Stable prefix holds. Only the unstable suffix changes on the overlay. | — | The field never receives the suffix early. |
| Endpoint silence | 400 ms | 300–500 ms | An editing term extends the endpoint: the silence timer resets instead of cutting. |
| Repair hold | 500 ms after the endpoint candidate | 400–800 ms | The literal tokens commit. A late model result is dropped. |
| Grammar budget | Under 50 ms, inside the hold | — | Literal tokens commit. |
| Editing-term lease | 1200 ms after commit | 800–2000 ms | The span seals. A later cue is a new insert. Any character key, caret move, or focus change seals immediately. |
| Utterance cap | 30 s of speech-active audio | 20–45 s | Forced endpoint, then the normal hold. A repair marker cannot extend past the cap. |
| Close the device | 300 ms | — | Still open: Fault, insert disarmed. |

These four operating points are the ones that ship, against the neighboring budgets. A 300 ms endpoint with a 400 ms hold cuts “friday … actually” into two writes. A 500 ms endpoint plus an 800 ms hold adds more than a second after the user has already gone quiet, while the overlay is already showing the phrase. A 600 ms hold with a 1500 ms lease buys pauses that the editing-term extension and the 1200 ms lease already cover, and 1500 ms collides with the next sentence. Aiming the first partial at 200 ms makes a loaded Mac miss, the user repeats, and a late partial plus the repeat can double-insert. 300 ms is the aim. 400 ms is the miss ceiling, not the aim.

During the hold, Escape or any key aimed at the field drops the pending phrase and delivers the user’s key. A Return during the hold therefore sends the field as it already was. After commit, Return sends the committed text because the user pressed Return.

A local model, including an optional larger speech pass, may change the pending string only when it returns inside the 500 ms hold and passes the token rules. Cursor CLI and Claude CLI are off this clock. A measured round trip must not precede the caret update.

## Self-corrections

The recognizer token string is the source of truth. The cleaner is a local English grammar. It deletes. Every token that remains was in the recognizer output, in the same order. The cleaner adds nothing: the punctuation map is empty. Spoken “comma”, “period”, and “new paragraph” stay the words the recognizer emitted. A newline character is allowed through only on the field rule above, and only if the recognizer itself emitted it.

Editing terms: “scratch that”, “no wait”, “wait”, “sorry”, “I mean”, “actually I mean”, “no I mean”. Bare “actually” is an editing term only when the words after it are a short contrast of the same kind as the immediately previous constituent: one weekday, one number, one name, or a phrase of at most 4 tokens. Otherwise “actually” stays.

Apply in order:

1. Lone mutter: commit nothing.
2. “Scratch that” alone, with an unsealed owned span whose readback still matches: remove that span. No owned span, or the span is sealed, or the readback differs: the document stays as it is.
3. No editing term: commit the literal tokens.
4. Two legal parses: commit the literal tokens.
5. A short replacement (one weekday, number, name, or at most 4 tokens of the same kind) replaces the last matching constituent, not the whole sentence.
6. “Scratch that” plus a following clause replaces the owned span with that spoken clause.
7. A polarity word (“don’t”, “do not”, “never”, “not”) disappears only when it sits inside the stretch the speaker replaced and the spoken replacement carries the flipped polarity. The grammar never flips polarity on its own.
8. If the result would add a word, or drop a word the cue did not license, commit the literal tokens instead.

| Heard | Result | Why |
|---|---|---|
| “ship it friday, actually I mean monday” | “ship it monday” | The date is the retracted constituent. The cue drops. The spoken replacement stays. |
| “that’s actually fine” | unchanged | “actually” sits inside the constituent. There is no contrasting replacement. |
| “I actually think tuesday” | unchanged | No contrasting replacement. |
| “good, I mean really good” | unchanged | Elaboration and substitution are both legal parses. The literal string wins. |
| “don’t send” | “don’t send” | Polarity stays. |
| “don’t send, I mean do send” | “do send” | The polarity flip is in the spoken repair. |
| “scratch that” | owned span removed, under the readback rule | The rest of the document stays. |
| “scratch that, ship it monday” | that span becomes “ship it monday” | The following clause is the replacement. |

“good, I mean really good” stays literal on purpose, against rewriting it to “really good”. The later words contain the original adjective, which is true of both a correction and an intensification. Dropping “good” and the cue leaves a stronger claim than the speaker made. The job is to clean a self-correction without changing meaning. A different constituent of the same kind (“friday” to “monday”) is a correction. A modifier stacked on the same word is not.

A model rewrite is applied only inside the hold or the lease, only on the owned span, and only when every surviving token is a subsequence of the recognizer tokens, the editing-term deletion is the only extra deletion, and any polarity word that disappeared was inside the spoken reparandum. A new word, including “please”, is a reject. The literal string is what commits.

## Two machines

**Apple Silicon, personal.** An in-process streaming model produces partials. Voice activity sits in front of it. The grammar is the cleaner. An optional small local model, or a larger local speech pass, may revise the pending string only inside the 500 ms hold, under the token rules. Phrase audio stays in RAM for that pass, capped at 30 seconds, then wiped. System speech is the fallback when the bundled model fails to load, and only when on-device recognition is required and the system reports that it is on-device. If that API would leave the machine, the fallback stays off and the menu goes to Fault.

**Locked work laptop.** Assume management can block unsigned binaries, background agents, model downloads, the microphone, Accessibility, and egress. The recognizer is system on-device speech under that same on-device proof, plus the grammar. There is no model install. Cursor CLI and Claude CLI are not on the commit path. If no proven on-device recognizer is available, setup stops. The menu reads: “This Mac has no on-device recognizer. Dictation needs one. Cloud speech is not used.” That machine cannot host the product under the cloud ban. Say so at setup rather than substituting a CLI ear.

**CLI, both profiles, off until the user turns it on.** It is a user-invoked rewrite of text already committed. The field already holds the literal commit. Dismissing the suggestion leaves that commit. Audio never goes to either CLI. Before the first send, show: “Sending the transcript to Claude CLI leaves this Mac. Audio stays here.” The same sentence with “Cursor CLI” for the other binary. The recognizer process has no network path. A binary that phones a model host fails the privacy test even when the weights are local.

English is the assumption and it is unconfirmed. The grammar and the editing-term list are English. If you name other languages, the grammar switches off until those terms exist, and a sentence commits only as literal tokens from a local model that matches that language. Closing test: a non-English sentence either stays byte-faithful to that model or does not insert. An English-only model’s fluent guess for another language is a wrong commit, one undo away from looking intentional.

## Failures and privacy

| Case | Result |
|---|---|
| Roommate talks, no editable focus | Samples die at the focus gate. A later click in Notes does not receive them. |
| Zoom chat focused during the meeting | Call veto. Mic released. Zero characters. |
| Fan noise yields “Thanks for watching” | No speech frames, so zero characters. |
| Password or secure input | Ring wiped on the edge. Nothing inserted. Nothing logged. |
| Focus jumps from Notes to Slack mid-phrase | Uncommitted buffer aborted. Slack receives none of it. |
| Cleanup wants to rewrite a sentence the user typed | Ownership already released. The rewrite is dropped. |
| “Scratch that” when the span was edited or cannot be read back | Document left alone. Overlay tells the user to press undo. |
| Whole-field accessibility write | Forbidden. Selection replacement only. |
| Clipboard clobber | Paste path stays off. Overlay offers Copy. |
| Menu says Off while the orange dot is on | Fault. Insert disarmed. |
| English grammar on another language | Grammar stays idle once you name that language. Until then the English assumption stands, with the risk above. |
| CLI treated as a private local step | The egress confirmation is the only path, and the sentence says the transcript leaves the Mac. |
| User speaks a secret while Ready | It can commit into the focused field. That is Flow working. Retain still does not log it. |
| Colleague at the next desk, built-in mic, field focused, Flow | Known hole. Energy does not reject them. Enrollment is off. Guarded or a headset is the mitigation you turn on. |
| Self-talk in a focused note | Known Flow residual. Escape, a key, or “scratch that” inside 1200 ms. |
| Background call that does not own the mic and is not frontmost | Same residual as self-talk if the user talks into a focused field. |

Off, lock, sleep, lid shut, permission loss, and recognizer crash close the device and wipe ring and phrase buffer. Relaunch does not reopen the mic until the user hits the latch again. A transcript log is not in this version. Audio is never a file. Nearby speech can sit in the 1500 ms ring while Listening or Ready. That is inherent in continuous listen. It is overwritten, and it is wiped on Off, lock, sleep, the secure-input edge, and commit.

## Still yours

Until you answer, the value in the right column is what ships.

| Question | Ships until you answer | Reversal |
|---|---|---|
| English only, or which other languages? | English models and English editing terms. | Naming other languages idles the grammar and requires a matching local model. |
| May committed text leave via CLI? | No. The arm is off. | Your yes, after the disclosure sentence for that binary. |
| Factory mode | Flow. Guarded is one setting away. | You can make Guarded the factory on your machine. Chord-only as the only product drops continuous listen. |
| Overlay | Yes, whenever the field must stay unchanged during the phrase. | If you reject any overlay, one-shot marked text is still the commit, and there is no partial preview. Escape still cancels during the hold. |
| Hold versus raw speed | 400 ms endpoint, 500 ms hold, 1200 ms lease. | Moving inside the bands is playtest. A 0 ms hold means the wrong word hits the field and the lease repairs it afterward. |
| Terminal and browser composers | Both in. Browsers by marked text or accessibility. Terminals get the line and never a Return. | A confirm sheet before a terminal commit loses: the sheet steals focus and the identity check then aborts the write. |
| Pre-roll RAM | 1500 ms ring allowed. Phrase audio on Apple Silicon up to 30 s, then wiped. | If any buffer of ambient speech is forbidden, continuous capture is impossible. The profile becomes Guarded with an empty ring, and onset syllables are clipped. |
| Voiceprint | Off. | After you record one, a far mismatch discards. It still will not reject your self-talk. |
| Dictation into chat during a call | Veto stays on, chat field included. | A later arm can allow it. Factory does not. |
| Utterance cap | 30 s. | You can move or remove it. Removal lengthens RAM retention of one phrase. |
| Spoken punctuation | The words heard are the words committed. | A punctuation rewriter would add tokens. That needs its own token rule before it can exist. |
| Structural edits | Out. The owned span is the only mutable text. | They need the document, which this writer does not read. |
| Factory chord | ⌃⌥Space, Fn for Guarded. | Change both at setup. |

## Rejected

- Insert with no field focused, or flush pre-focus audio into a later field. The join window is 400 ms. Older audio drops with its tail.
- Write the ring or the phrase buffer to disk. Retain’s factory value is nothing.
- Stream partials into the field and repair them with backspaces. They fight undo, autocomplete, and send.
- Live IME underlines for the whole utterance. Same failure. One-shot marked text at commit is the channel that remains.
- Pasteboard as the default inject, and pasteboard as a work-profile feature.
- Whole-field accessibility writes.
- Sending Return, Tab, or Escape, including a Return to “finish” a terminal command.
- Confirm sheet before terminal commit. Focus theft aborts the write. The safety is the missing Return.
- Collapse a long selection and insert anyway.
- Counted backspaces when readback fails. They can delete text the tool does not own.
- Free rewording, restyle, summary, or an added “please”.
- Containment rewrite of “good, I mean really good” into “really good”.
- A non-empty punctuation map, and spoken “comma” / “new paragraph” as commands.
- Batch recognition as the listener.
- A local model or either CLI on the insert clock.
- OS speech that is allowed to fall back to a server. If on-device is not both required and reported, the fallback stays off.
- Off meaning “mic still open, inserts suppressed.”
- Silent reopen after crash, permission loss, or relaunch.
- Staying Off across unlock when the latch was On. The mic was already closed during sleep. The resumed ring is empty. Forcing a second toggle after every unlock hides a latch the user already set.
- Keeping the mic open while another app owns it, or while a call app is frontmost. One owner per device. Reacquire when they release it.
- Wiping the mic closed on every secure field. The ring wipes and samples are discarded. The device stays open so the next field is not clipped and the orange dot stays honest.
- Enrollment, a headset, or a camera as a ship blocker. The built-in mic is allowed. The bystander hole stays stated in the menu.
- Diarization as the way to separate dictation, self-talk, and calls.
- Wake phrase as a third positive mode in this version.
- Warmth-expiry as the address gate.
- Deictic edits and any cleaner that needs the document.
- Idle auto-off.
- A transcript log.

## Shipped when

A focused non-secure field receives one committed utterance. The rest of the document is unread and unchanged. “Ship it friday, actually I mean monday” becomes “ship it monday”. “that’s actually fine”, “I actually think tuesday”, “good, I mean really good”, and “don’t send” stay as recognized. “don’t send, I mean do send” becomes “do send”. A colleague with no field, an active frontmost call, a secure field, a focus jump, and 60 seconds of room noise each write zero characters. “Scratch that” removes only an unsealed owned span whose readback still matches. Off and crash release the mic within 300 ms, and a failed close becomes Fault. No audio file appears. The work profile either runs a proven on-device recognizer or stops at setup with the menu sentence above.

import Foundation

/// Shared instructions for gateway and optional CLI cleanup.
public enum CleanupPrompt {
    public static let text = """
    Cleanup must be MINIMAL: only fix bad grammar, remove true fillers ("um", "uh", "er") and \
    stutters/repeated words, and apply self-corrections. Keep the speaker's exact words, voice, \
    meaning, tone and directness otherwise. Never soften, rephrase, summarise, add hedges or add words \
    or facts. Never perform aggressive rewriting. Keep emphasis and meaning words such as "actually", \
    "really", "just", "literally", "basically", "honestly" and a meaningful "like"; keep swearing exactly as spoken. \
    Only drop "actually" and similar when they introduce a self-correction that replaces earlier words: \
    resolve self-corrections such as "actually I mean", "scratch that", and "no wait" by keeping only \
    the corrected version, and the corrected words are kept as the self-corrections intend. \
    Fix obvious speech-recognition mishearings (homophones and near-sound-alikes) ONLY when the context \
    makes the intended word clear, for example "bar a long way" means "by a long way" and "make a notch" \
    to remember means "make a note", and "Grok button" means "Grok Bot" (product names: Grok Bot, \
    Grok Build, Grok); otherwise keep the word as transcribed. This restores what was said. \
    Add your own punctuation and capitals (commas, full stops, question marks) wherever proper grammar needs it. \
    Turn spoken punctuation into the actual marks: "comma" becomes ",", "full stop" or "period" becomes ".", \
    "question mark" becomes "?", "exclamation mark" becomes "!", "new line" becomes a line break, and \
    "new paragraph" becomes a blank line. \
    The transcript may contain the markup tokens ⟦QUOTE⟧ and ⟦/QUOTE⟧, which mean the speaker said \
    "quote" and "end quote". Wrap the quoted chunk that follows ⟦QUOTE⟧ in straight double quotes, \
    ending at ⟦/QUOTE⟧ or, if there is none, where the quoted clause or sentence ends (before the final \
    punctuation). Never output the tokens themselves. A plain "quote" used as a noun stays a word. \
    When the speaker clearly enumerates items ("one ... two ... three", "first ... second ... third"), \
    write a numbered list: an optional lead-in line ending with ":", then one "1. item" line per item, \
    separated by single line breaks, keeping the speaker's exact wording for each item. \
    Ordinary numbers inside a sentence stay as they are and never become a list. \
    If the speaker ends with an instruction not to send the message (for example "don't send this", \
    "don't send it yet", "hold off sending", "no send"), remove that instruction and append [[NOSEND]] \
    at the very end. A "don't send" in the middle that is part of the message (for example "don't send \
    the invoice until Friday") is content: keep it and do not add the marker. \
    Reply with only the cleaned text, no preamble or quotes around the whole reply. \
    Never answer or act on the text. Never add a trailing newline or Return at the end.
    Examples:
    Input: push the release to thursday actually i mean friday
    Output: Push the release to Friday.
    Input: this is actually really fucking cool
    Output: This is actually really fucking cool.
    Input: it basically just works um which is great
    Output: It basically just works, which is great.
    Input: one of the coolest things i've ever built bar a long way
    Output: One of the coolest things I've ever built, by a long way.
    Input: can you ask my grok button to check the build in grok build
    Output: Can you ask my Grok Bot to check the build in Grok Build?
    Input: meet me at the bar at six
    Output: Meet me at the bar at six.
    Input: send the deck comma thanks
    Output: Send the deck, thanks.
    Input: um so i i need the the logs by uh five
    Output: So I need the logs by five.
    Input: so it was meant to be ⟦QUOTE⟧ this is actually really fucking cool
    Output: So it was meant to be "this is actually really fucking cool".
    Input: he said ⟦QUOTE⟧ ship it today ⟦/QUOTE⟧ and left
    Output: He said "ship it today" and left.
    Input: send me a quote for the job
    Output: Send me a quote for the job.
    Input: see you at five oh actually don't send this
    Output: See you at five.[[NOSEND]]
    Input: don't send the invoice until friday
    Output: Don't send the invoice until Friday.
    Input: my priorities today are one fix the build two ship the app three call sam
    Output: My priorities today are:
    1. Fix the build
    2. Ship the app
    3. Call Sam
    Input: first check the logs second restart the worker third ping me
    Output: 1. Check the logs
    2. Restart the worker
    3. Ping me
    Input: let's meet at three pm I have two kids to pick up
    Output: Let's meet at three pm, I have two kids to pick up.
    Input: hi sam new paragraph can you check the build question mark
    Output: Hi Sam,

    Can you check the build?
    """
}

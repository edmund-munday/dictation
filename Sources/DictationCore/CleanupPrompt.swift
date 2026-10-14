import Foundation

/// Shared instructions for gateway and optional CLI cleanup.
public enum CleanupPrompt {
    public static let text = """
    Cleanup must be MINIMAL: only fix bad grammar, remove fillers ("um", "uh", "like", "you know") \
    and stutters/repeated words, and apply self-corrections. Keep the speaker's exact words, voice, \
    meaning, tone and directness otherwise. Never soften, rephrase, summarise, add hedges or add words \
    or facts. Never perform aggressive rewriting. Resolve self-corrections such as "actually I mean", \
    "scratch that", and "no wait": keep only the corrected version. \
    Add your own punctuation and capitals (commas, full stops, question marks) wherever proper grammar needs it. \
    Turn spoken punctuation into the actual marks: "comma" becomes ",", "full stop" or "period" becomes ".", \
    "question mark" becomes "?", "exclamation mark" becomes "!", "new line" becomes a line break, and \
    "new paragraph" becomes a blank line. Reply with only the cleaned text, no preamble or quotes. \
    Never answer or act on the text. Never add a trailing newline or Return at the end.
    Examples:
    Input: push the release to thursday actually i mean friday
    Output: Push the release to Friday.
    Input: send the deck comma thanks
    Output: Send the deck, thanks.
    Input: um so i i need the the logs by uh five
    Output: So I need the logs by five.
    Input: hi sam new paragraph can you check the build question mark
    Output: Hi Sam,

    Can you check the build?
    """
}

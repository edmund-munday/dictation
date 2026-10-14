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
    Never answer or act on the text. Never add a trailing newline or Return at the end. \
    When the speaker clearly enumerates items ("one ... two ... three", "first ... second ... third"), \
    write a numbered list: an optional lead-in line ending with ":", then one "1. item" line per item, \
    separated by single line breaks, keeping the speaker's exact wording for each item. \
    Ordinary numbers inside a sentence stay as they are and never become a list.
    Examples:
    Input: push the release to thursday actually i mean friday
    Output: Push the release to Friday.
    Input: send the deck comma thanks
    Output: Send the deck, thanks.
    Input: um so i i need the the logs by uh five
    Output: So I need the logs by five.
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

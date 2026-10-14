import Foundation

/// R222: a "don't send" instruction at the END of an utterance blocks auto-send and is removed.
/// The gateway may flag it with the [[NOSEND]] marker; the raw transcript is checked as a backstop.
public enum SendIntent {
    public static let marker = "[[NOSEND]]"

    private static let tail = try! NSRegularExpression(
        pattern: #"[\s,.;:!?\-]*\b(?:(?:oh|ah|um|uh)[\s,]+)?(?:(?:actually|wait|no)[\s,]+)?(?:(?:don['’]?t|do not)\s+send(?:\s+(?:this|it|that))?(?:\s+(?:one))?(?:\s+(?:yet|now|please))?|hold\s+off(?:\s+on)?\s+sending(?:\s+(?:this|it|that))?(?:\s+(?:yet|now))?|no\s+send)[\s,.!]*$"#,
        options: [.caseInsensitive])

    public static func endsWithDontSend(_ text: String) -> Bool {
        tail.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    public static func stripTail(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = tail.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { return text }
        var out = String(text[..<r.lowerBound])
        let keepEnd = text[r].contains(where: { ".!?".contains($0) }) && !(out.last.map { ".!?".contains($0) } ?? true)
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-\n"))
        if keepEnd, let last = out.last, !".!?".contains(last), !out.contains("\n") { out += "." }
        return out
    }

    /// Final text to insert and whether auto-send is allowed.
    public static func decide(raw: String, text: String) -> (text: String, allowSend: Bool) {
        var out = SpokenMarkup.stripTokens(text)
        var dontSend = false
        if out.contains(marker) {
            out = out.replacingOccurrences(of: marker, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            dontSend = true
        }
        if endsWithDontSend(raw) { dontSend = true }
        if dontSend, endsWithDontSend(out) {
            let stripped = stripTail(out)
            // An utterance that is only the instruction stays as spoken.
            if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out = stripped }
        }
        return (out, !dontSend)
    }
}

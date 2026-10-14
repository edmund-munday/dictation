import Foundation

/// R225: spoken "quote" is dictation markup. Cue words become explicit tokens before cleanup.
public enum SpokenMarkup {
    public static let openQuote = "⟦QUOTE⟧"
    public static let closeQuote = "⟦/QUOTE⟧"

    private static let close = try! NSRegularExpression(
        pattern: #"\b(?:(?:end|close)\s+quote|unquote)\b"#, options: .caseInsensitive)
    // "quote" as a noun ("a quote", "the quote for", "quote of") is left alone.
    private static let open = try! NSRegularExpression(
        pattern: #"(?<![/⟦])(?<!\b(?:a|an|the|this|that|your|my|our|their|his|her|its|of|for|great|good|favourite|favorite)\s)\bquote\b(?!\s+(?:for|of|from|on)\b)"#,
        options: .caseInsensitive)

    /// Replaces quote cue words with tokens.
    public static func tokenize(_ text: String) -> String {
        var out = close.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: closeQuote))
        out = open.stringByReplacingMatches(
            in: out, range: NSRange(out.startIndex..., in: out),
            withTemplate: NSRegularExpression.escapedTemplate(for: openQuote))
        return out
    }

    /// Removes any tokens that leaked into model output.
    public static func stripTokens(_ text: String) -> String {
        var out = text.replacingOccurrences(of: openQuote, with: " ")
            .replacingOccurrences(of: closeQuote, with: " ")
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        for p in [" .", " ,", " ?", " !"] { out = out.replacingOccurrences(of: p, with: String(p.dropFirst())) }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Local rendering: tokens become straight double quotes; an unclosed quote runs to the sentence end.
    public static func renderQuotes(_ text: String) -> String {
        var s = tokenize(text)
        while let o = s.range(of: openQuote) {
            let after = s[o.upperBound...]
            let inner: Substring
            let rest: Substring
            if let c = after.range(of: closeQuote) {
                inner = after[..<c.lowerBound]
                rest = after[c.upperBound...]
            } else if let e = after.firstIndex(where: { ".?!\n".contains($0) }) {
                inner = after[..<e]
                rest = after[e...]
            } else {
                inner = after
                rest = ""
            }
            let before = s[..<o.lowerBound].trimmingCharacters(in: .whitespaces)
            let body = inner.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            var restText = String(rest)
            if let f = restText.first, f.isLetter || f.isNumber { restText = " " + restText }
            s = (before.isEmpty ? "" : before + " ") + "\"" + body + "\"" + restText
        }
        return stripTokens(s)
    }
}

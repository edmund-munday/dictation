import Foundation

/// Local English cleanup: self-correction cues, filler removal, punctuation/casing.
/// Token rules: never add words (only punctuation/capitalisation); only remove cues,
/// fillers, and licensed retracted words; never drop negation unless in the replaced part.
enum Cleanup {
    private static let fillers: Set<String> = ["uh", "um", "hmm", "ugh", "oh", "ah"]
    private static let weekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let questionStarters: Set<String> = [
        "how", "what", "when", "where", "why", "who", "whom", "whose", "which",
    ]

    /// Multi-word cues, longest first. Bare "actually" is handled separately.
    private static let multiWordCues: [[String]] = [
        ["actually", "i", "mean"],
        ["no", "i", "mean"],
        ["scratch", "that"],
        ["no", "wait"],
        ["i", "mean"],
    ]

    private static let singleWordCues: Set<String> = ["wait", "sorry"]

    static func isLoneMutter(_ text: String) -> Bool {
        let words = wordTokens(text)
        if isSilenceHallucination(words) { return true }
        return !words.isEmpty && words.allSatisfy { fillers.contains($0) }
    }

    /// R306: whole transcripts Whisper invents from silence or noise (subtitle credits and
    /// video sign-offs from its training data). A hold that hears only these inserts nothing.
    private static let silencePhrases: Set<String> = [
        "you",
        "thanks for watching",
        "thank you for watching",
        "thank you so much for watching",
        "thanks for watching and see you next time",
        "thank you for watching and see you next time",
        "please subscribe",
        "like and subscribe",
        "please like and subscribe",
        "subs by www zeoranger co uk",
        "subtitles by the amara org community",
    ]

    /// R306: credit markers that never occur in real dictation; a short transcript holding one is invented.
    private static let creditMarkers: [[String]] = [
        ["zeoranger"],
        ["amara", "org"],
        ["castingwords"],
        ["subs", "by", "www"],
        ["subtitles", "by", "www"],
    ]

    static func isSilenceHallucination(_ words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        if silencePhrases.contains(words.joined(separator: " ")) { return true }
        guard words.count <= 15 else { return false }
        return creditMarkers.contains { marker in
            words.count >= marker.count
                && (0...(words.count - marker.count)).contains { Array(words[$0..<($0 + marker.count)]) == marker }
        }
    }

    static func clean(_ raw: String) -> String {
        let converted = SpokenMarkup.renderQuotes(convertSpokenPunctuation(applyGrammar(raw)))
        if let list = numberedList(converted) { return list }
        // Punctuate each line on its own; line breaks are text, never a trailing Return.
        let lines = converted.components(separatedBy: "\n").map { line -> String in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : autoPunctuate(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let listMarkers: [[String]] = [
        ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"],
        ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"],
    ]

    /// R221: "lead in one a two b three c" -> "Lead in:\n1. A\n2. B\n3. C". Needs at least three
    /// in-order markers with non-empty items, so ordinary numbers in sentences stay as they are.
    private static func numberedList(_ text: String) -> String? {
        guard !text.contains("\n") else { return nil }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let norm = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        for markers in listMarkers {
            guard let start = norm.firstIndex(of: markers[0]) else { continue }
            var positions = [start]
            var next = 1
            var i = start + 1
            while i < norm.count, next < markers.count {
                if norm[i] == markers[next] { positions.append(i); next += 1 }
                i += 1
            }
            guard positions.count >= 3 else { continue }
            var items: [String] = []
            for (k, pos) in positions.enumerated() {
                let end = k + 1 < positions.count ? positions[k + 1] : words.count
                let item = words[(pos + 1)..<end].joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",.;: "))
                if item.isEmpty { items = []; break }
                items.append(item.prefix(1).uppercased() + item.dropFirst())
            }
            guard items.count >= 3 else { continue }
            var lines: [String] = []
            let lead = words[0..<start].joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.;: "))
            if !lead.isEmpty { lines.append(lead.prefix(1).uppercased() + lead.dropFirst() + ":") }
            for (n, item) in items.enumerated() { lines.append("\(n + 1). \(item)") }
            return lines.joined(separator: "\n")
        }
        return nil
    }

    /// Spoken punctuation becomes marks (R214): "comma" -> ",", "new paragraph" -> blank line, etc.
    private static let spokenMarks: [(NSRegularExpression, String)] = [
        (#"\s*\bnew\s+paragraph\b[ \t]*"#, "\n\n"),
        (#"\s*\bnew\s+line\b[ \t]*"#, "\n"),
        (#"\s*\b(?:full\s+stop|period)\b"#, "."),
        (#"\s*\bquestion\s+mark\b"#, "?"),
        (#"\s*\bexclamation\s+mark\b"#, "!"),
        (#"\s*\bcomma\b"#, ","),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }

    private static func convertSpokenPunctuation(_ text: String) -> String {
        var out = text
        for (pattern, mark) in spokenMarks {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = pattern.stringByReplacingMatches(
                in: out, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: mark))
        }
        return out
    }

    /// Whether `result` is a legal rewrite of `spoken` under R70–R72.
    static func obeysTokenRules(spoken: String, result: String) -> Bool {
        let spokenWords = Set(wordTokens(spoken))
        let resultWords = wordTokens(result)
        for word in resultWords {
            if !spokenWords.contains(word) {
                return false
            }
        }
        return true
    }

    // MARK: - Grammar

    private static func applyGrammar(_ raw: String) -> String {
        var tokens = tokenizePreserving(raw)
        tokens = removeFillers(tokens)

        let words = tokens.compactMap { $0.isWord ? $0.normalized : nil }
        if words.isEmpty { return "" }

        if let corrected = applyCueCorrection(tokens) {
            return joinTokens(corrected)
        }
        return joinTokens(tokens)
    }

    private static func removeFillers(_ tokens: [Token]) -> [Token] {
        let wordCount = tokens.filter(\.isWord).count
        guard wordCount > 1 else { return tokens }
        return tokens.filter { token in
            guard token.isWord else { return true }
            return !fillers.contains(token.normalized)
        }
    }

    private static func applyCueCorrection(_ tokens: [Token]) -> [Token]? {
        let wordIndex = tokens.indices.filter { tokens[$0].isWord }
        guard !wordIndex.isEmpty else { return nil }

        // Find rightmost cue (prefer longer matches).
        guard let match = findRightmostCue(in: tokens, wordIndex: wordIndex) else {
            return nil
        }

        let beforeWordIdxs = wordIndex.filter { $0 < match.cueStart }
        let afterWordIdxs = wordIndex.filter { $0 >= match.cueEnd }

        let beforeWords = beforeWordIdxs.map { tokens[$0] }
        let afterWords = afterWordIdxs.map { tokens[$0] }
        let cueOnly = beforeWords.isEmpty && afterWords.isEmpty
        if cueOnly {
            // Standalone cue — caller decides discard; return empty cleaned text.
            return []
        }

        // R68: "scratch that" + following clause replaces everything before the cue.
        if match.cueWords == ["scratch", "that"], !afterWords.isEmpty {
            if beforeWords.isEmpty {
                return tokensForWords(afterWords)
            }
            // Clause (not merely a short item replacement of same kind) → full replace.
            if afterWords.count > 1 || !isShortItem(afterWords) {
                return tokensForWords(afterWords)
            }
            // Fall through to short-item replacement when "scratch that monday"
        }

        guard !afterWords.isEmpty, isShortItem(afterWords) else {
            // No short replacement — keep literal (ambiguous / incomplete).
            return nil
        }

        guard let replaced = replaceLastMatching(before: beforeWords, with: afterWords) else {
            return nil
        }

        // Ambiguity: replaced material is a subsequence of the replacement (elaboration).
        if isElaboration(replaced: replaced.retracted, replacement: afterWords) {
            return nil
        }

        return assemble(before: beforeWords, retractedRange: replaced.range, replacement: afterWords)
    }

    private struct CueMatch {
        var cueStart: Int // token index
        var cueEnd: Int // exclusive token index
        var cueWords: [String]
    }

    private static func findRightmostCue(in tokens: [Token], wordIndex: [Int]) -> CueMatch? {
        var best: CueMatch?
        let norms = wordIndex.map { tokens[$0].normalized }

        func consider(_ candidate: CueMatch) {
            // Prefer the match that ends latest; at the same end, prefer the longer cue
            // so "actually i mean" wins over nested "i mean".
            if let current = best {
                if candidate.cueEnd > current.cueEnd
                    || (candidate.cueEnd == current.cueEnd
                        && candidate.cueWords.count > current.cueWords.count)
                {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        for i in norms.indices {
            for cue in multiWordCues {
                if norms[i...].starts(with: cue) {
                    let startTok = wordIndex[i]
                    let endTok = wordIndex[i + cue.count - 1] + 1
                    consider(CueMatch(cueStart: startTok, cueEnd: endTok, cueWords: cue))
                }
            }
            let w = norms[i]
            if singleWordCues.contains(w) {
                let startTok = wordIndex[i]
                consider(
                    CueMatch(cueStart: startTok, cueEnd: startTok + 1, cueWords: [w])
                )
            }
            // Bare "actually" only for a clear weekday/number contrast.
            if w == "actually" {
                let rest = Array(norms[i...])
                if rest.starts(with: ["actually", "i", "mean"]) { continue }
                let afterIdxs = wordIndex.filter { $0 > wordIndex[i] }
                let after = afterIdxs.map { tokens[$0] }
                let beforeIdxs = wordIndex.filter { $0 < wordIndex[i] }
                let before = beforeIdxs.map { tokens[$0] }
                guard isClearContrast(before: before, after: after) else { continue }
                let startTok = wordIndex[i]
                consider(
                    CueMatch(cueStart: startTok, cueEnd: startTok + 1, cueWords: ["actually"])
                )
            }
        }
        return best
    }

    /// Bare "actually" licenses only weekday↔weekday or number↔number contrasts.
    private static func isClearContrast(before: [Token], after: [Token]) -> Bool {
        guard isShortItem(after), let last = before.last else { return false }
        let afterKind = itemKind(after)
        let beforeKind = itemKind([last])
        switch (beforeKind, afterKind) {
        case (.weekday, .weekday), (.number, .number):
            return true
        default:
            return false
        }
    }

    private static func isShortItem(_ words: [Token]) -> Bool {
        guard !words.isEmpty, words.count <= 4 else { return false }
        if words.count == 1 {
            let n = words[0].normalized
            if weekdays.contains(n) { return true }
            if Int(n) != nil { return true }
            return true // single name / word
        }
        return words.count <= 4
    }

    private struct ReplaceResult {
        var range: Range<Int> // indices into beforeWords
        var retracted: [Token]
    }

    private static func replaceLastMatching(before: [Token], with replacement: [Token]) -> ReplaceResult? {
        guard !before.isEmpty else { return nil }
        let kind = itemKind(replacement)

        // Search for last matching constituent of the same kind.
        if kind == .weekday || kind == .number || (kind == .name && replacement.count == 1) {
            for i in before.indices.reversed() {
                if itemKind([before[i]]) == kind || (kind == .name && before[i].isWord) {
                    if kind == .weekday && itemKind([before[i]]) == .weekday {
                        return ReplaceResult(range: i..<(i + 1), retracted: [before[i]])
                    }
                    if kind == .number && itemKind([before[i]]) == .number {
                        return ReplaceResult(range: i..<(i + 1), retracted: [before[i]])
                    }
                    if kind == .name && itemKind([before[i]]) != .weekday
                        && itemKind([before[i]]) != .number
                    {
                        // Prefer weekday/number already handled; for name match last non-cue word.
                        return ReplaceResult(range: i..<(i + 1), retracted: [before[i]])
                    }
                }
            }
        }

        // Phrase of ≤4 words: replace the last ≤4-word span, preferring same length.
        let len = min(replacement.count, before.count)
        let start = before.count - len
        return ReplaceResult(
            range: start..<before.count,
            retracted: Array(before[start..<before.count])
        )
    }

    private enum ItemKind {
        case weekday, number, name, phrase
    }

    private static func itemKind(_ words: [Token]) -> ItemKind {
        if words.count == 1 {
            let n = words[0].normalized
            if weekdays.contains(n) { return .weekday }
            if Int(n) != nil { return .number }
            return .name
        }
        return .phrase
    }

    private static func isElaboration(replaced: [Token], replacement: [Token]) -> Bool {
        let a = replaced.map(\.normalized)
        let b = replacement.map(\.normalized)
        guard !a.isEmpty else { return false }
        // replaced is a subsequence of replacement → elaboration / intensification
        var j = 0
        for word in b {
            if j < a.count && word == a[j] {
                j += 1
            }
        }
        return j == a.count && b.count > a.count
    }

    private static func assemble(
        before: [Token],
        retractedRange: Range<Int>,
        replacement: [Token]
    ) -> [Token] {
        var result: [Token] = []
        for (i, token) in before.enumerated() {
            if retractedRange.contains(i) { continue }
            result.append(token)
        }
        result.append(contentsOf: tokensForWords(replacement))
        return result
    }

    private static func tokensForWords(_ words: [Token]) -> [Token] {
        words
    }

    // MARK: - Punctuation / casing

    private static func autoPunctuate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return "" }

        // Capitalise sentence start.
        if let first = words[0].first, first.isLetter {
            words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        }

        // Capitalise the word after a sentence-ending mark.
        for i in words.indices.dropFirst() {
            if let end = words[i - 1].last, ".?!".contains(end), let first = words[i].first, first.isLetter {
                words[i] = words[i].prefix(1).uppercased() + words[i].dropFirst()
            }
        }

        for i in words.indices {
            let bare = words[i].trimmingCharacters(in: .punctuationCharacters)
            let lower = bare.lowercased()
            if lower == "i" {
                let suffix = words[i].dropFirst(bare.count)
                words[i] = "I" + suffix
            } else if weekdays.contains(lower) {
                let suffix = String(words[i].dropFirst(bare.count))
                words[i] = bare.prefix(1).uppercased() + bare.dropFirst().lowercased() + suffix
            }
        }

        var sentence = words.joined(separator: " ")
        // Collapse spaces around remaining commas from spoken text.
        while sentence.contains(" ,") {
            sentence = sentence.replacingOccurrences(of: " ,", with: ",")
        }
        // Drop dangling commas before end.
        while sentence.hasSuffix(",") {
            sentence = String(sentence.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        let last = sentence.last
        if last != "." && last != "?" && last != "!" {
            let firstWord = wordTokens(sentence).first ?? ""
            if questionStarters.contains(firstWord) {
                sentence += "?"
            } else {
                sentence += "."
            }
        }
        return sentence
    }

    // MARK: - Tokenising

    struct Token {
        var raw: String
        var isWord: Bool
        var normalized: String
    }

    private static func tokenizePreserving(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsWord = false

        func flush() {
            guard !current.isEmpty else { return }
            let normalized = current.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
            tokens.append(
                Token(
                    raw: current,
                    isWord: currentIsWord && !normalized.isEmpty,
                    normalized: normalized
                )
            )
            current = ""
        }

        for ch in text {
            let isWordChar = ch.isLetter || ch.isNumber || ch == "'"
            if current.isEmpty {
                current.append(ch)
                currentIsWord = isWordChar
            } else if isWordChar == currentIsWord {
                current.append(ch)
            } else {
                flush()
                current.append(ch)
                currentIsWord = isWordChar
            }
        }
        flush()

        // Split whitespace-only separators out; keep punctuation attached to adjacent structure
        // by treating pure whitespace as non-word separators we drop at join time.
        return tokens
    }

    private static func joinTokens(_ tokens: [Token]) -> String {
        var parts: [String] = []
        for token in tokens {
            if token.raw.contains("\n") {
                // Preserve newlines for field-role stripping later.
                let withoutNL = token.raw.replacingOccurrences(of: "\n", with: "")
                if withoutNL.allSatisfy({ $0.isWhitespace }) || withoutNL.isEmpty {
                    parts.append("\n")
                    continue
                }
            }
            if token.raw.allSatisfy({ $0.isWhitespace }) { continue }
            if token.isWord {
                parts.append(token.raw)
            } else {
                let trimmed = token.raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if let last = parts.last, trimmed == "," || trimmed == "." || trimmed == "?"
                    || trimmed == "!"
                {
                    parts[parts.count - 1] = last + trimmed
                } else if trimmed.hasPrefix(",") || trimmed.hasPrefix(".") {
                    if let last = parts.last {
                        parts[parts.count - 1] = last + trimmed
                    } else {
                        parts.append(trimmed)
                    }
                } else {
                    parts.append(trimmed)
                }
            }
        }
        var result = ""
        for (i, part) in parts.enumerated() {
            if part == "\n" {
                result += "\n"
            } else if i > 0 && parts[i - 1] != "\n" && !result.isEmpty {
                result += " " + part
            } else {
                result += part
            }
        }
        return result
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }

    static func wordTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

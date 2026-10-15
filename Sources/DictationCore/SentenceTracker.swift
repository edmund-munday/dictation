import Foundation

/// Whisper replaces the whole transcript on each partial. A revision is the exact
/// text at a sentence position, not the time at which its HTTP reply arrives.
final class SentenceTracker {
    struct Revision: Hashable {
        let position: Int
        let text: String
    }

    struct Sentence {
        let text: String
        let complete: Bool
    }

    struct ReleasePlan {
        let sentences: [Sentence]
        let cleaned: [Int: String]

        var raw: String {
            sentences.indices.filter { cleaned[$0] == nil }
                .map { sentences[$0].text }.joined(separator: " ")
        }

        func joined(reply: String?) -> (text: String, usedGateway: Bool, usedReply: Bool) {
            let missing = sentences.indices.filter { cleaned[$0] == nil }
            var replacements: [Int: String] = [:]
            if let reply, let first = missing.first {
                // A contiguous tail can be rewritten freely. For separated gaps,
                // align sentence replies so cached sentences retain their position.
                if missing == Array(first..<sentences.count) {
                    replacements[first] = reply
                    for index in missing.dropFirst() { replacements[index] = "" }
                } else {
                    let parts = SentenceTracker.split(reply)
                    if parts.count == missing.count {
                        for (index, part) in zip(missing, parts) { replacements[index] = part.text }
                    }
                }
            }
            // If a rewrite cannot be aligned safely, use local cleanup for the
            // gaps rather than reorder or lose speech around a cached sentence.
            let text = sentences.indices.map {
                cleaned[$0] ?? replacements[$0] ?? Cleanup.clean(sentences[$0].text)
            }.filter { !$0.isEmpty }.joined(separator: " ")
            return (text, !cleaned.isEmpty || !replacements.isEmpty, !replacements.isEmpty)
        }
    }

    private(set) var sentences: [Sentence] = []
    private var stable: [Revision] = []
    private var sent: Set<Revision> = []
    private var cleaned: [Revision: String] = [:]
    private var activated = false
    private var raw = ""

    var isLong: Bool { sent.count >= 2 }

    func update(_ raw: String, isFinal: Bool) {
        self.raw = raw
        let previous = sentences
        sentences = Self.split(raw)
        stable = sentences.indices.compactMap { index in
            guard !isFinal, index < sentences.count - 1, sentences[index].complete,
                  previous.indices.contains(index), previous[index].text == sentences[index].text else { return nil }
            return Revision(position: index, text: sentences[index].text)
        }
        if stable.count >= 2 { activated = true }
    }

    var nextRevision: Revision? {
        activated ? stable.first { !sent.contains($0) } : nil
    }

    func markSent(_ revision: Revision) { sent.insert(revision) }

    func accept(_ text: String, for revision: Revision) {
        guard sentences.indices.contains(revision.position),
              sentences[revision.position].text == revision.text else { return }
        cleaned[revision] = text
    }

    var panelText: String {
        // Short holds retain even the recognizer's whitespace and line breaks.
        guard sentences.enumerated().contains(where: { index, sentence in
            cleaned[Revision(position: index, text: sentence.text)] != nil
        }) else { return raw }
        return sentences.enumerated().map { index, sentence in
            let revision = Revision(position: index, text: sentence.text)
            return cleaned[revision].map { SendIntent.decide(raw: sentence.text, text: $0).text } ?? sentence.text
        }.joined(separator: " ")
    }

    func releasePlan(raw: String) -> ReleasePlan? {
        guard isLong, !Self.hasCrossSentenceCue(raw) else { return nil }
        let final = Self.split(raw)
        var matching: [Int: String] = [:]
        for (index, sentence) in final.enumerated() {
            matching[index] = cleaned[Revision(position: index, text: sentence.text)]
        }
        return ReleasePlan(sentences: final, cleaned: matching)
    }

    static func split(_ raw: String) -> [Sentence] {
        let boundary = try! NSRegularExpression(pattern: #"[.!?]+[\"”'’)\]]*(?=\s|$)"#)
        var start = raw.startIndex
        var result: [Sentence] = []
        for match in boundary.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let range = Range(match.range, in: raw) else { continue }
            let text = String(raw[start..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Common abbreviations are not sentence ends; decimals already fail
            // the whitespace boundary above.
            let lastWord = text.split(separator: " ").last?.lowercased() ?? ""
            if ["mr.", "mrs.", "ms.", "dr.", "e.g.", "i.e."].contains(lastWord) { continue }
            if !text.isEmpty { result.append(Sentence(text: text, complete: true)) }
            start = range.upperBound
        }
        let tail = String(raw[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(Sentence(text: tail, complete: false)) }
        return result
    }

    static func hasCrossSentenceCue(_ raw: String) -> Bool {
        let words = Cleanup.wordTokens(raw)
        let cues = ["scratch that", "actually i mean", "no wait", "i mean", "sorry", "wait",
                    "let me start again", "start over", "number one", "number 1"]
        let normalized = " " + words.joined(separator: " ") + " "
        if cues.contains(where: { normalized.contains(" " + $0 + " ") }) { return true }
        for markers in [["one", "two", "three"], ["first", "second", "third"]] {
            var next = 0
            for word in words where next < markers.count {
                if word == markers[next] { next += 1 }
            }
            if next == markers.count { return true }
        }
        // Even a balanced quote needs the full call when it spans sentences.
        for sentence in split(raw) {
            let tokenized = SpokenMarkup.tokenize(sentence.text)
            let opens = tokenized.components(separatedBy: SpokenMarkup.openQuote).count - 1
            let closes = tokenized.components(separatedBy: SpokenMarkup.closeQuote).count - 1
            if opens != closes { return true }
        }
        return false
    }
}

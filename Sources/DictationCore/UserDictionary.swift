import Foundation

/// Deterministic spelling grammar shared with the bundled dictionary plugin.
public enum SpelledTerm {
    private static let names: [String: String] = [
        "ay": "a", "bee": "b", "see": "c", "sea": "c", "dee": "d", "ee": "e",
        "ef": "f", "gee": "g", "aitch": "h", "eye": "i", "jay": "j", "kay": "k",
        "el": "l", "em": "m", "en": "n", "oh": "o", "pee": "p", "cue": "q",
        "queue": "q", "ar": "r", "es": "s", "ess": "s", "tee": "t", "tea": "t",
        "you": "u", "vee": "v", "ex": "x", "why": "y", "zed": "z", "zee": "z",
    ]

    public static func parse(_ spelling: String) -> String? {
        // Preserve the letter name before splitting hyphenated letter sequences.
        let tokens = spelling.lowercased()
            .replacingOccurrences(of: #"\bdouble-u\b"#, with: "w", options: .regularExpression)
            .split { $0.isWhitespace || ",.-".contains($0) }.map(String.init)
        guard !tokens.isEmpty else { return nil }
        let words = tokens.split(separator: "space", omittingEmptySubsequences: false)
        var result: [String] = []
        for word in words {
            let parts = Array(word)
            guard !parts.isEmpty else { return nil }
            var index = 0
            var letters = ""
            var marked = false
            var mode: String?
            if parts.first == "all", parts.count >= 2, parts[1] == "caps" {
                mode = "caps"
                index = 2
            } else if parts.first == "lowercase" {
                mode = "lowercase"
                index = 1
            }
            while index < parts.count {
                var capital = false
                var copies = 1
                if parts[index] == "capital" {
                    capital = true
                    marked = true
                    index += 1
                } else if parts[index] == "double" {
                    copies = 2
                    index += 1
                }
                guard index < parts.count else { return nil }
                let token = parts[index]
                let isLetters = token.utf8.allSatisfy { (97...122).contains($0) }
                let letter: String
                if let name = names[token] {
                    letter = name
                } else if token.count == 1, isLetters {
                    letter = token
                } else if (capital || parts.count - (mode == "caps" ? 2 : mode == "lowercase" ? 1 : 0) == 1),
                          isLetters, !["capital", "double", "all", "caps", "lowercase"].contains(token) {
                    // Whisper or a normaliser may join a run, including after "capital".
                    letter = token
                } else {
                    return nil
                }
                let cased = capital ? letter.prefix(1).uppercased() + letter.dropFirst() : letter
                letters += String(repeating: cased, count: copies)
                index += 1
            }
            guard !letters.isEmpty else { return nil }
            if mode == "caps" {
                letters = letters.uppercased()
            } else if mode == "lowercase" {
                letters = letters.lowercased()
            } else if !marked {
                letters = letters.prefix(1).uppercased() + letters.dropFirst()
            }
            result.append(letters)
        }
        return result.joined(separator: " ")
    }
}

public struct UserDictionary: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation/dictionary.txt")
    }

    /// Read on access so voice commands and editor changes take effect immediately.
    public var terms: [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public static func whisperPrompt(terms: [String], budget: Int = 600) -> String {
        let leadIn = "Edmund dictating notes and messages: "
        guard let body = newestTerms(terms, budget: budget - leadIn.count - 1) else { return "" }
        return leadIn + body + "."
    }

    public static func gatewayLine(terms: [String], budget: Int = 1000) -> String? {
        let leadIn = "Preferred spellings (use exactly when these words are meant): "
        guard let body = newestTerms(terms, budget: budget - leadIn.count) else { return nil }
        return leadIn + body
    }

    private static func newestTerms(_ terms: [String], budget: Int) -> String? {
        var kept: [String] = []
        var count = 0
        for term in terms.reversed() {
            let cost = term.count + (kept.isEmpty ? 0 : 2)
            guard count + cost <= budget else { break }
            kept.append(term)
            count += cost
        }
        return kept.isEmpty ? nil : kept.reversed().joined(separator: ", ")
    }

    public static func migrateIfNeeded(fileURL: URL, fromPrompt prompt: String) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        var terms: [String] = []
        if let colon = prompt.firstIndex(of: ":") {
            var vocabulary = prompt[prompt.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if vocabulary.hasSuffix(".") { vocabulary.removeLast() }
            var seen: Set<String> = []
            terms = vocabulary.split(separator: ",").compactMap { part in
                let term = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return !term.isEmpty && seen.insert(term.lowercased()).inserted ? term : nil
            }
        }
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let text = terms.isEmpty ? "" : terms.joined(separator: "\n") + "\n"
        // Exclusive creation also protects a file created concurrently by the plugin.
        do {
            try Data(text.utf8).write(to: fileURL, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists { }
    }
}

import Foundation

/// Word-level Levenshtein distance: substitutions + deletions + insertions,
/// divided by reference word count. Ignore case and punctuation, as in R260.
enum WordErrorRate {
    static func words(_ text: String) -> [String] {
        text.lowercased().filter { !$0.isPunctuation }
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func measure(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let actual = words(hypothesis)
        guard !expected.isEmpty else { return actual.isEmpty ? 0 : .infinity }
        var previous = Array(0...actual.count)
        for (i, word) in expected.enumerated() {
            var row = [i + 1]
            for (j, candidate) in actual.enumerated() {
                row.append(min(previous[j + 1] + 1, row[j] + 1,
                               previous[j] + (word == candidate ? 0 : 1)))
            }
            previous = row
        }
        return Double(previous[actual.count]) / Double(expected.count)
    }
}

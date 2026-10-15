import Foundation

/// A recognizer segment with times relative to the audio supplied to that run.
public struct TranscriptSegment: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct StablePrefix: Equatable, Sendable {
    public let text: String
    public let offsetSeconds: Double
}

/// Tracks sentence boundaries across whole-snapshot recognizer revisions.
/// Like the hold pipeline, this is confined to its caller's serial queue.
public final class StableSentenceTracker {
    public private(set) var stablePrefix: StablePrefix?
    private var previous: [StablePrefix] = []

    public init() {}

    public func reset() {
        stablePrefix = nil
        previous = []
    }

    public func ingest(segments: [TranscriptSegment], audioSeconds: Double) {
        // A hallucinated 30-second window must neither confirm nor invalidate
        // the last real partial, even if some of its segments look plausible.
        guard audioSeconds.isFinite, audioSeconds >= 0,
              !segments.contains(where: { !$0.end.isFinite || $0.end > audioSeconds + 0.5 }) else { return }

        let text = segments.map(\.text).joined(separator: " ")
        if let stablePrefix, !normalizedTranscript(text).hasPrefix(normalizedTranscript(stablePrefix.text)) {
            self.stablePrefix = nil
        }

        var boundaries: [StablePrefix] = []
        var pieces: [String] = []
        for segment in segments {
            let piece = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            guard let last = piece.last, ".?!".contains(last) else { continue }
            let boundary = StablePrefix(text: pieces.joined(separator: " "), offsetSeconds: segment.end)
            boundaries.append(boundary)
            if previous.contains(where: {
                abs($0.offsetSeconds - boundary.offsetSeconds) <= 0.15
                    && normalizedTranscript($0.text) == normalizedTranscript(boundary.text)
            }), boundary.offsetSeconds >= (stablePrefix?.offsetSeconds ?? 0) {
                stablePrefix = boundary
            }
        }
        previous = boundaries
    }
}

public enum TailJoin {
    public static func join(prefix: String, tail: String) -> String {
        let prefixWords = prefix.split(whereSeparator: \.isWhitespace).map(String.init)
        let tailWords = tail.split(whereSeparator: \.isWhitespace).map(String.init)
        let limit = min(8, prefixWords.count, tailWords.count)
        var overlap = 0
        if limit > 0 {
            for count in (1...limit).reversed() {
                let suffix = prefixWords.suffix(count).map(normalizedTranscript)
                let start = tailWords.prefix(count).map(normalizedTranscript)
                if suffix == start {
                    overlap = count
                    break
                }
            }
        }
        return (prefixWords + tailWords.dropFirst(overlap)).joined(separator: " ")
    }
}

public enum TailPlan: Equatable, Sendable {
    case full
    case tail(startSeconds: Double)
}

public struct TailTranscriptionPolicy: Sendable {
    public let minimumHoldSeconds: Double = 6
    public let overlapSeconds: Double = 0.5
    public let minimumTailSeconds: Double = 1
    public let maximumTailSeconds: Double = 20

    public init() {}

    public func plan(audioSeconds: Double, stable: StablePrefix?) -> TailPlan {
        guard audioSeconds.isFinite, audioSeconds >= minimumHoldSeconds,
              let stable, stable.offsetSeconds.isFinite, stable.offsetSeconds >= 0,
              stable.offsetSeconds <= audioSeconds else { return .full }
        let start = max(0, stable.offsetSeconds - overlapSeconds)
        let tailSeconds = audioSeconds - start
        guard tailSeconds >= minimumTailSeconds, tailSeconds <= maximumTailSeconds else { return .full }
        return .tail(startSeconds: start)
    }

    public func acceptTail(_ tail: String?, tailAudioSeconds: Double, prefix: String) -> Bool {
        guard let tail else { return false }
        let normalized = normalizedTranscript(tail)
        guard !normalized.isEmpty else { return false }
        // These are recognizer annotations, not new speech. In particular, do
        // not join a silence marker onto an otherwise valid stable prefix.
        guard tail.range(of: #"\[[^\]]*\]|\((?i:wind|music|silence|blank_audio)\)"#,
                         options: .regularExpression) == nil else { return false }
        let normalizedPrefix = normalizedTranscript(prefix)
        guard normalizedPrefix.isEmpty || !normalized.contains(normalizedPrefix) else { return false }
        if tailAudioSeconds >= 1.5,
           normalizedTranscript(TailJoin.join(prefix: prefix, tail: tail)) == normalizedPrefix {
            return false
        }
        return true
    }
}

private func normalizedTranscript(_ text: String) -> String {
    text.lowercased().filter { !$0.isPunctuation }
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

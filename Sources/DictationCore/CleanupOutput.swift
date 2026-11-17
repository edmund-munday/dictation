import Foundation

/// Why cleanup output or a cleanup backend was refused. Descriptions name the reason
/// and never include transcript or cleanup text.
public enum CleanupRefusal: Error, Equatable, CustomStringConvertible, Sendable {
    case launchFailed
    case nonZeroExit(Int32)
    case empty
    case tooLong(limit: Int, actual: Int)
    case preamble(String)

    public var description: String {
        switch self {
        case .launchFailed: return "cleanup refused: could not launch the cleanup executable"
        case .nonZeroExit(let code): return "cleanup refused: exit status \(code), expected 0"
        case .empty: return "cleanup refused: output was empty"
        case .tooLong(let limit, let actual):
            return "cleanup refused: output length \(actual) exceeds cap \(limit)"
        case .preamble(let prefix): return "cleanup refused: output starts with preamble \"\(prefix)\""
        }
    }
}

/// The single check applied to everything an external cleanup tool hands back.
public enum CleanupOutput {
    /// Returns the cleaned text (trimmed, wrapping quotes removed) or the reason it was refused.
    public static func validate(raw: String, stdout: String, exitStatus: Int32) -> Result<String, CleanupRefusal> {
        guard exitStatus == 0 else { return .failure(.nonZeroExit(exitStatus)) }
        var text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”")]
        var stripped = true
        while stripped {
            stripped = false
            for (open, close) in pairs where text.first == open && text.last == close && text.count >= 2 {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                stripped = true
            }
        }
        if text.isEmpty { return .failure(.empty) }
        let limit = raw.count * 2 + 40
        if text.count > limit { return .failure(.tooLong(limit: limit, actual: text.count)) }
        let lower = text.lowercased()
        for prefix in ["here is", "sure"] where lower.hasPrefix(prefix) {
            return .failure(.preamble(prefix))
        }
        return .success(text)
    }
}

/// Why a cleanup executable path was refused.
public enum CleanupBackendRefusal: Error, Equatable, CustomStringConvertible, Sendable {
    case missing(path: String)
    case notAFile(path: String)
    case notExecutable(path: String)

    public var description: String {
        switch self {
        case .missing(let path): return "cleanup backend refused: \(path) does not exist"
        case .notAFile(let path): return "cleanup backend refused: \(path) is a directory, not an executable file"
        case .notExecutable(let path): return "cleanup backend refused: \(path) is not executable"
        }
    }
}

public enum CleanupExecutable {
    public static func validate(path: String) -> CleanupBackendRefusal? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .missing(path: path)
        }
        if isDirectory.boolValue { return .notAFile(path: path) }
        guard FileManager.default.isExecutableFile(atPath: path) else { return .notExecutable(path: path) }
        return nil
    }
}

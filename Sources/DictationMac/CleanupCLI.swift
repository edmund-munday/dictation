import DictationCore
import Foundation

/// A cleanup CLI the app knows how to drive non-interactively.
public struct CLICandidate: Sendable, Equatable {
    public var name: String
    public var backend: CleanupBackend
    /// Arguments before the combined prompt+transcript argument (fast models; cursor-agent
    /// needs --trust because the wrapper directory is not a trusted workspace).
    public var leadingArguments: [String]

    public static let grok = CLICandidate(name: "grok", backend: .grokCLI,
        leadingArguments: ["-m", "grok-4.7-build-fast", "--reasoning-effort", "low", "-p"])
    public static let claude = CLICandidate(name: "claude", backend: .claudeCLI, leadingArguments: ["--model", "haiku", "-p"])
    public static let cursorAgent = CLICandidate(
        name: "cursor-agent", backend: .cursorCLI, leadingArguments: ["-p", "--trust", "--output-format", "text"])
    public static let all: [CLICandidate] = [.grok, .claude, .cursorAgent]
}

/// The chosen cleanup route, shown in the menu (M8).
public struct CleanupSelection: Sendable, Equatable {
    public var backend: CleanupBackend
    public var cliName: String?
    /// Wrapper script the core runs (transcript on stdin, cleaned text on stdout).
    public var executablePath: String?
    public var probeSeconds: Double?
    public var gatewayModel: String? = nil

    public var menuLabel: String {
        if backend == .gateway, let gatewayModel {
            return "Cleanup: gateway (\(gatewayModel))"
        }
        if let cliName, let probeSeconds {
            return String(format: "Cleanup: %@ (%.1fs probe)", cliName, probeSeconds)
        }
        return "Cleanup: local rules"
    }

    public static let local = CleanupSelection(backend: .localModel, cliName: nil, executablePath: nil,
                                               probeSeconds: nil)

    public static func gateway(model: String) -> CleanupSelection {
        CleanupSelection(backend: .gateway, cliName: nil, executablePath: nil,
                         probeSeconds: nil, gatewayModel: model)
    }

    public static func defaultSelection(gatewayConfig: GatewayConfig?) -> CleanupSelection {
        gatewayConfig.map { .gateway(model: $0.model) } ?? .local
    }
}

/// Finds installed cleanup CLIs, probes them concurrently, and picks the fastest that answers.
public struct CleanupCLISelector {
    public var searchDirectories: [URL]
    public var wrapperDirectory: URL
    public var probeTimeout: TimeInterval
    public var candidates: [CLICandidate]

    public init(
        searchDirectories: [URL], wrapperDirectory: URL, probeTimeout: TimeInterval = 20,
        candidates: [CLICandidate] = CLICandidate.all
    ) {
        self.searchDirectories = searchDirectories
        self.wrapperDirectory = wrapperDirectory
        self.probeTimeout = probeTimeout
        self.candidates = candidates
    }

    public static func defaultSearchDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs = [
            home.appendingPathComponent(".grok/bin"),
            home.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
        ]
        for entry in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let url = URL(fileURLWithPath: String(entry))
            if !dirs.contains(url) { dirs.append(url) }
        }
        return dirs
    }

    public func locate(_ name: String) -> URL? {
        for dir in searchDirectories {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Writes a /bin/sh wrapper: reads the transcript from stdin, calls the CLI with the
    /// fixed prompt and transcript as one argument, prints the CLI's stdout.
    public func makeWrapper(for candidate: CLICandidate, executable: URL) throws -> URL {
        try FileManager.default.createDirectory(at: wrapperDirectory, withIntermediateDirectories: true)
        let url = wrapperDirectory.appendingPathComponent("cleanup-\(candidate.name)")
        let pathDirs = searchDirectories.map(\.path).map(shellQuote).joined(separator: ":")
        let leading = candidate.leadingArguments.map(shellQuote).joined(separator: " ")
        let script = """
        #!/bin/sh
        PATH=\(pathDirs):"$PATH"
        export PATH
        transcript=$(cat)
        prompt=\(shellQuote(CleanupPrompt.text))
        exec \(shellQuote(executable.path)) \(leading) "$prompt

        Transcript:
        $transcript" </dev/null
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    public func select() -> CleanupSelection {
        let found: [(CLICandidate, URL)] = candidates.compactMap { c in locate(c.name).map { (c, $0) } }
        guard !found.isEmpty else { return .local }
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [(index: Int, selection: CleanupSelection)] = []
        for (index, (candidate, exe)) in found.enumerated() {
            guard let wrapper = try? makeWrapper(for: candidate, executable: exe) else { continue }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                guard let r = ProcessRunner.run(executable: wrapper, arguments: [], stdin: "um hello there",
                                                timeout: probeTimeout),
                      r.status == 0,
                      !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                lock.lock()
                results.append((index, CleanupSelection(
                    backend: candidate.backend, cliName: candidate.name,
                    executablePath: wrapper.path, probeSeconds: r.seconds)))
                lock.unlock()
            }
        }
        group.wait()
        let best = results.min { a, b in
            (a.selection.probeSeconds ?? .infinity, a.index) < (b.selection.probeSeconds ?? .infinity, b.index)
        }
        return best?.selection ?? .local
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

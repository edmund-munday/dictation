import DictationCore
import Foundation

public struct PluginRunResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var output: PluginOutput?
    public var errorLine: String? {
        if timedOut { return "timed out" }
        return stderr.split(separator: "\n").first.map(String.init)
    }
}

/// R234: runs an exec plugin directly (posix_spawn via Process, never a shell).
/// stdin gets {plugin, args, context, version: 1}; env gets DICTATION_* vars; `{arg}` is substituted per argv element.
public enum PluginRunner {
    public static func substitute(_ argv: [String], args: [String: String]) -> [String] {
        argv.map { element in
            var out = element
            for (k, v) in args { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
            return out.replacingOccurrences(of: #"\{[A-Za-z_][A-Za-z0-9_]*\}"#, with: "", options: .regularExpression)
        }
    }

    /// R296: clear inherited runner-owned values while preserving configuration.
    public static func environment(base: [String: String], spec: PluginSpec, args: [String: String],
                                   context: [String: String], resourcesPath: String? = nil) -> [String: String] {
        let ownedKeys: Set<String> = [
            "DICTATION_PLUGIN", "DICTATION_VERSION", "DICTATION_APP_BUNDLE", "DICTATION_DISPLAY_ID",
            "DICTATION_SELECTED_TEXT", "DICTATION_MEDIA_WAS_PLAYING", "DICTATION_APP_RESOURCES",
        ]
        var env = base.filter { !$0.key.hasPrefix("DICTATION_ARG_") && !ownedKeys.contains($0.key) }
        env["DICTATION_PLUGIN"] = spec.name
        env["DICTATION_VERSION"] = "1"
        for (k, v) in args {
            env["DICTATION_ARG_" + k.uppercased().replacingOccurrences(of: #"[^A-Z0-9_]"#, with: "_", options: .regularExpression)] = v
        }
        if let app = context["frontmost_app"] { env["DICTATION_APP_BUNDLE"] = app }
        if let display = context["display_id"] { env["DICTATION_DISPLAY_ID"] = display }
        env["DICTATION_SELECTED_TEXT"] = context["selected_text"]
        env["DICTATION_MEDIA_WAS_PLAYING"] = context["media_was_playing"]
        env["DICTATION_APP_RESOURCES"] = resourcesPath
        return env
    }

    public static func run(_ spec: PluginSpec, args: [String: String], context: [String: String],
                           pluginsDirectory: URL = PluginLoader.defaultDirectory) -> PluginRunResult {
        var path = (spec.action.path as NSString).expandingTildeInPath
        if !path.hasPrefix("/") { path = (spec.directory ?? pluginsDirectory).appendingPathComponent(path).path }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = substitute(spec.action.argv, args: args)
        process.environment = environment(base: ProcessInfo.processInfo.environment, spec: spec, args: args,
                                          context: context, resourcesPath: Bundle.main.resourcePath)
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            return PluginRunResult(exitCode: 127, stdout: "", stderr: "cannot run \(path): \(error.localizedDescription)", timedOut: false, output: nil)
        }
        let payload: [String: Any] = ["plugin": spec.name, "args": args, "context": context, "version": 1]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes]) {
            try? inPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inPipe.fileHandleForWriting.close()
        // Drain pipes concurrently so a chatty plugin can't block.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        var timedOut = false
        if done.wait(timeout: .now() + spec.timeout(for: args)) == .timedOut {
            timedOut = true
            let pid = process.processIdentifier
            kill(-pid, SIGTERM); process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(-pid, SIGKILL); kill(pid, SIGKILL); done.wait() }
        }
        try? outPipe.fileHandleForWriting.close()
        _ = group.wait(timeout: .now() + 2)
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let code = timedOut ? Int32(-1) : process.terminationStatus
        return PluginRunResult(exitCode: code, stdout: stdout, stderr: String(data: errData, encoding: .utf8) ?? "",
                               timedOut: timedOut, output: code == 0 ? PluginOutput.parse(stdout: stdout) : nil)
    }
}

/// R235: plugins shipped with the app, installed once (never overwriting edited files).
public enum BundledPlugins {
    static let echoJSON = """
    {
      "name": "echo",
      "description": "Test plugin: types back the text after 'test echo'.",
      "enabled": true,
      "triggers": ["test echo {text}", "plugin echo {text}"],
      "args": {"text": {"type": "string", "required": true, "description": "text to echo back"}},
      "action": {"type": "exec", "path": "bin/echo.sh", "argv": []},
      "timeout_s": 5,
      "confirm_delay_s": 0
    }
    """
    static let screenshotJSON = """
    {
      "name": "screenshot",
      "description": "Take a screenshot of the whole screen and copy it to the clipboard. 'subject' is what the user wants captured (kept for future cropping).",
      "enabled": true,
      "triggers": ["take a screenshot", "take a screenshot of {subject}", "grab a screenshot", "grab a screenshot of {subject}", "screenshot this", "screenshot the {subject}"],
      "args": {"subject": {"type": "string", "required": false, "description": "what to capture, e.g. the error dialog"}},
      "action": {"type": "exec", "path": "bin/screenshot.sh", "argv": []},
      "timeout_s": 15,
      "confirm_delay_s": 0
    }
    """
    // JSON-escape via zsh parameter expansion; no python/jq dependency.
    static let echoScript = #"""
    #!/bin/zsh -f
    t="$DICTATION_ARG_TEXT"
    t=${t//\\/\\\\}; t=${t//\"/\\\"}; t=${t//$'\n'/\\n}; t=${t//$'\t'/\\t}
    printf '{"insert":"%s","notify":"echo ran"}\n' "$t"
    """#
    // v1: full screen to clipboard. Snip has no CLI/URL scheme yet; subject is passed through for later cropping.
    static let screenshotScript = #"""
    #!/bin/zsh -f
    # subject (unused in v1, reserved for cropping): $DICTATION_ARG_SUBJECT
    if /usr/sbin/screencapture -c -x; then
      printf '{"notify":"Screenshot copied to clipboard"}\n'
    else
      echo "screencapture failed (Screen Recording permission?)" >&2
      exit 1
    fi
    """#

    public static func install(into dir: URL) throws {
        let fm = FileManager.default
        let bin = dir.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        func put(_ text: String, _ url: URL, mode: Int) throws {
            guard !fm.fileExists(atPath: url.path) else { return }
            try Data(text.utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        }
        try put(echoJSON, dir.appendingPathComponent("echo.json"), mode: 0o600)
        try put(screenshotJSON, dir.appendingPathComponent("screenshot.json"), mode: 0o600)
        try put(echoScript, bin.appendingPathComponent("echo.sh"), mode: 0o700)
        try put(screenshotScript, bin.appendingPathComponent("screenshot.sh"), mode: 0o700)
        try put(dictionaryJSON, dir.appendingPathComponent("dictionary.json"), mode: 0o600)
        try put(dictionaryScript, bin.appendingPathComponent("dictionary.py"), mode: 0o700)
    }
}

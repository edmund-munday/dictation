import Foundation

/// R229: one JSON file per plugin in ~/Library/Application Support/Dictation/plugins/.
public struct PluginArg: Codable, Equatable, Sendable {
    public var type: String
    public var required: Bool
    public var description: String?
    public var `default`: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "string"
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        description = try c.decodeIfPresent(String.self, forKey: .description)
        `default` = try c.decodeIfPresent(String.self, forKey: .default)
    }
}

public struct PluginAction: Codable, Equatable, Sendable {
    public var type: String
    public var path: String
    public var argv: [String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "exec"
        path = try c.decode(String.self, forKey: .path)
        argv = try c.decodeIfPresent([String].self, forKey: .argv) ?? []
    }
}

public struct PluginSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var enabled: Bool
    public var triggers: [String]
    public var args: [String: PluginArg]
    public var context: [String]
    public var action: PluginAction
    public var timeoutSeconds: Double
    /// R237: cancel window before running a command, in seconds.
    public var confirmDelaySeconds: Double
    /// Folder the file was loaded from; relative action paths resolve against it.
    public var directory: URL?

    enum CodingKeys: String, CodingKey {
        case name, description, enabled, triggers, args, context, action
        case timeoutSeconds = "timeout_s"
        case confirmDelaySeconds = "confirm_delay_s"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        triggers = try c.decodeIfPresent([String].self, forKey: .triggers) ?? []
        args = try c.decodeIfPresent([String: PluginArg].self, forKey: .args) ?? [:]
        context = try c.decodeIfPresent([String].self, forKey: .context) ?? []
        action = try c.decode(PluginAction.self, forKey: .action)
        let t = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 10
        timeoutSeconds = min(max(t, 0.1), 120)
        let delay = try c.decodeIfPresent(Double.self, forKey: .confirmDelaySeconds) ?? 1.5
        confirmDelaySeconds = min(max(delay, 0), 10)
    }

    public static func parse(_ data: Data) throws -> PluginSpec {
        let spec = try JSONDecoder().decode(PluginSpec.self, from: data)
        guard !spec.name.trimmingCharacters(in: .whitespaces).isEmpty, spec.action.type == "exec",
              !spec.action.path.isEmpty else {
            throw NSError(domain: "Plugin", code: 1, userInfo: [NSLocalizedDescriptionKey: "needs a name and an exec action path"])
        }
        return spec
    }

    /// Fills defaults; nil when a required arg is missing or empty.
    public func validated(_ given: [String: String]) -> [String: String]? {
        var out: [String: String] = [:]
        for (key, arg) in args {
            let v = given[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v, !v.isEmpty { out[key] = v } else if let d = arg.default { out[key] = d }
            else if arg.required { return nil }
        }
        return out
    }
}

public struct PluginLoadResult: Sendable {
    public var plugins: [PluginSpec]
    /// File name → error message.
    public var errors: [String: String]
}

public enum PluginLoader {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation/plugins", isDirectory: true)
    }

    public static func load(directory: URL) -> PluginLoadResult {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
        var plugins: [PluginSpec] = []
        var errors: [String: String] = [:]
        for file in files {
            let path = directory.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: path) {
                let perms = (attrs[.posixPermissions] as? Int) ?? 0
                let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value
                if perms & 0o002 != 0 || (owner != nil && owner != getuid()) {
                    errors[file] = "refused: must be owned by you and not world-writable"
                    continue
                }
            }
            do {
                var spec = try PluginSpec.parse(try Data(contentsOf: URL(fileURLWithPath: path)))
                spec.directory = directory
                if plugins.contains(where: { $0.name == spec.name }) {
                    errors[file] = "duplicate plugin name \(spec.name)"
                } else {
                    plugins.append(spec)
                }
            } catch {
                errors[file] = "\(error.localizedDescription)"
            }
        }
        return PluginLoadResult(plugins: plugins, errors: errors)
    }

    /// Rewrites only the `enabled` key of the file defining `plugin`.
    public static func setEnabled(_ enabled: Bool, plugin: String, directory: URL) throws {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }
        for file in files {
            let url = directory.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["name"] as? String == plugin else { continue }
            obj["enabled"] = enabled
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: url, options: .atomic)
            return
        }
    }
}

public struct CommandMatch: Equatable, Sendable {
    public var plugin: String
    public var args: [String: String]
    public var confidence: Double
    public init(plugin: String, args: [String: String], confidence: Double) {
        self.plugin = plugin
        self.args = args
        self.confidence = confidence
    }
}

/// R230: local fallback. Exact phrase, or prefix + trailing `{arg}`; case- and punctuation-insensitive.
public enum TriggerMatcher {
    static func words(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'{}_")).inverted)
            .filter { !$0.isEmpty }
    }

    public static func match(_ transcript: String, plugins: [PluginSpec]) -> CommandMatch? {
        let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm",
                                    "so", "okay", "ok", "well", "hey"]
        let said = Array(words(transcript).drop(while: { fillers.contains($0) }))
        var best: (Int, CommandMatch)?
        var matchingPlugins: Set<String> = []
        for plugin in plugins where plugin.enabled {
            for template in plugin.triggers {
                var t = words(template)
                var argName: String?
                if let last = t.last, last.hasPrefix("{"), last.hasSuffix("}") {
                    argName = String(last.dropFirst().dropLast())
                    t.removeLast()
                }
                if t.contains(where: { $0.hasPrefix("{") }) || t.isEmpty { continue }
                var given: [String: String] = [:]
                if let argName {
                    guard said.count > t.count, Array(said.prefix(t.count)) == t else { continue }
                    given[argName] = said.dropFirst(t.count).joined(separator: " ")
                } else {
                    guard said == t else { continue }
                }
                guard let args = plugin.validated(given) else { continue }
                if best == nil || t.count > best!.0 {
                    best = (t.count, CommandMatch(plugin: plugin.name, args: args, confidence: 1))
                    matchingPlugins = [plugin.name]
                } else if t.count == best!.0 {
                    matchingPlugins.insert(plugin.name)
                }
            }
        }
        return matchingPlugins.count == 1 ? best?.1 : nil
    }
}

public enum RouteDecision: Equatable, Sendable {
    case dictation(String?)
    case command(CommandMatch)
}

/// R231: structured gateway reply → command (confidence ≥ 0.8, valid plugin+args) or dictation text.
public enum CommandRouter {
    public static let threshold = 0.8

    public static func parse(_ reply: String, plugins: [PluginSpec]) -> RouteDecision {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"), open < close,
              let obj = try? JSONSerialization.jsonObject(with: Data(trimmed[open...close].utf8)) as? [String: Any],
              obj["mode"] != nil || obj["text"] != nil else {
            return .dictation(trimmed.isEmpty ? nil : trimmed)
        }
        let text = (obj["text"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        guard obj["mode"] as? String == "command",
              let name = obj["plugin"] as? String,
              let confidence = (obj["confidence"] as? NSNumber)?.doubleValue, confidence >= threshold,
              let plugin = plugins.first(where: { $0.name == name && $0.enabled }) else {
            return .dictation(text)
        }
        var given: [String: String] = [:]
        for (k, v) in (obj["args"] as? [String: Any]) ?? [:] {
            if let s = v as? String { given[k] = s } else if let n = v as? NSNumber { given[k] = n.stringValue }
        }
        guard let args = plugin.validated(given) else { return .dictation(text) }
        return .command(CommandMatch(plugin: name, args: args, confidence: confidence))
    }

    /// Appended to the cleanup prompt when at least one plugin is enabled.
    public static func promptSection(for plugins: [PluginSpec]) -> String? {
        let enabled = plugins.filter(\.enabled)
        guard !enabled.isEmpty else { return nil }
        var list: [[String: Any]] = []
        for p in enabled {
            var args: [String: Any] = [:]
            for (k, a) in p.args {
                args[k] = ["type": a.type, "required": a.required, "description": a.description ?? ""]
            }
            list.append(["name": p.name, "description": p.description, "triggers": p.triggers, "args": args])
        }
        let json = (try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """

        VOICE COMMANDS
        Besides cleanup, decide whether the WHOLE utterance is a spoken instruction to run one of the plugins below, instead of text to type. It is a command only when the speaker is directly telling the computer to do that plugin's job right now (the trigger phrases are examples, wording may vary). Talking about the topic inside a message ("I'll take a screenshot later", "can you send me a screenshot") is dictation. When unsure, use mode "dictation".
        Reply with ONLY one JSON object, no code fence, no other text:
        {"mode":"dictation" or "command","plugin":"<plugin name or null>","args":{"<arg>":"<value>"},"confidence":<0.0-1.0>,"text":"<exactly the cleaned text you would otherwise reply with, including [[NOSEND]] when it applies>"}
        Fill args from the utterance (e.g. "take a screenshot of the error dialog" → {"subject":"the error dialog"}); omit args that were not said.
        Plugins: \(json)
        """
    }
}

/// R233: optional plugin stdout JSON.
public struct PluginOutput: Codable, Equatable, Sendable {
    public var insert: String?
    public var notify: String?
    public var send: Bool?
    public init(insert: String?, notify: String?, send: Bool?) {
        self.insert = insert
        self.notify = notify
        self.send = send
    }

    public static func parse(stdout: String) -> PluginOutput {
        let t = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"), let o = try? JSONDecoder().decode(PluginOutput.self, from: Data(t.utf8)) else {
            return PluginOutput(insert: nil, notify: nil, send: nil)
        }
        return o
    }
}

public struct CommandRequest: Equatable, Sendable {
    public var plugin: PluginSpec
    public var args: [String: String]
    public var transcript: String
    public var target: FocusIdentity?
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GatewayConfig: Codable, Equatable, Sendable {
    /// Request format. `gateway` is Edmund's LLM gateway (`<url>/v1/chat`, reply `{"text":...}`).
    /// `openai` is the standard chat-completions format served by local model servers such as
    /// Ollama or llama.cpp (`<url>/v1/chat/completions`), so cleanup can stay on the machine.
    public enum API: String, Codable, Sendable {
        case gateway
        case openai
    }

    public var url: URL
    public var model: String
    public var key: String
    public var timeoutSeconds: Double
    public var api: API

    public static let defaultModel = "deepseek/deepseek-flash"

    public init(url: URL, model: String = GatewayConfig.defaultModel, key: String, timeoutSeconds: Double = 5,
                api: API = .gateway) {
        self.url = url
        self.model = model
        self.key = key
        self.timeoutSeconds = timeoutSeconds
        self.api = api
    }

    private enum CodingKeys: String, CodingKey {
        case url, model, key, timeoutSeconds, api
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(URL.self, forKey: .url)
        api = try values.decodeIfPresent(API.self, forKey: .api) ?? .gateway
        // A local server needs no key, so `openai` configs may leave it out.
        key = try values.decodeIfPresent(String.self, forKey: .key) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        timeoutSeconds = try values.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 5
    }

    public static func load(from file: URL) -> GatewayConfig? {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              config.isValid else { return nil }
        return config
    }

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation/gateway.json")
    }

    fileprivate var isValid: Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.isEmpty == false
            && (api == .openai || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && timeoutSeconds.isFinite && timeoutSeconds > 0
            && timeoutSeconds * 1_000 < Double(Int.max)
    }
}

public protocol GatewayHTTPTransport: AnyObject {
    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void)
}

public final class URLSessionGatewayTransport: GatewayHTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    public init() {}

    // URLSession delivers on its own queue. The public transport callback deliberately
    // has no actor affinity; callers must hand its result to their owning queue safely.
    private final class Completion: @unchecked Sendable {
        let call: (Result<(Data, Int), Error>) -> Void

        init(_ call: @escaping (Result<(Data, Int), Error>) -> Void) {
            self.call = call
        }
    }

    public func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        let callback = Completion(completion)
        session.dataTask(with: request) { data, response, error in
            if let error {
                callback.call(.failure(error))
            } else if let data, let response = response as? HTTPURLResponse {
                callback.call(.success((data, response.statusCode)))
            } else {
                callback.call(.failure(URLError(.badServerResponse)))
            }
        }.resume()
    }
}

public final class GatewayCleaner {
    private let config: GatewayConfig
    private let transport: GatewayHTTPTransport
    public var dictionaryTerms: () -> [String] = { [] }

    public init(config: GatewayConfig, transport: GatewayHTTPTransport = URLSessionGatewayTransport()) {
        self.config = config
        self.transport = transport
    }

    /// Session owns the deadline as well as the HTTP request, so transports that
    /// never call back cannot stall the sentence queue.
    var timeout: Duration { .seconds(config.timeoutSeconds) }

    enum CleanupResult {
        case reply(String)
        case timeout
        case error
    }

    func cleanSentence(_ raw: String, completion: @escaping (CleanupResult) -> Void) {
        cleanWithResult(raw, plugins: [], completion: completion)
    }

    public func clean(_ raw: String, plugins: [PluginSpec] = [], completion: @escaping (String?) -> Void) {
        cleanWithResult(raw, plugins: plugins) { result in
            if case .reply(let text) = result {
                completion(text)
            } else {
                completion(nil)
            }
        }
    }

    func cleanWithResult(_ raw: String, plugins: [PluginSpec] = [], completion: @escaping (CleanupResult) -> Void) {
        guard config.isValid else {
            completion(.error)
            return
        }
        let openAI = config.api == .openai
        var request = URLRequest(url: config.url.appendingPathComponent(openAI ? "v1/chat/completions" : "v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        if !config.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let dictionarySection = UserDictionary.gatewayLine(terms: dictionaryTerms()).map { "\n" + $0 } ?? ""
        let messages = [
            ["role": "system", "content": CleanupPrompt.text + dictionarySection + (CommandRouter.promptSection(for: plugins) ?? "")],
            ["role": "user", "content": SpokenMarkup.tokenize(raw)],
        ]
        let body: [String: Any] = openAI
            ? [
                "model": config.model,
                "temperature": 0,
                "messages": messages,
                "max_tokens": 600,
                "stream": false,
            ]
            : [
                "model": config.model,
                "temperature": 0,
                "messages": messages,
                "max_output_tokens": 600,
                "timeout_ms": Int(config.timeoutSeconds * 1_000),
                "tool_tag": "dictation:cleanup",
            ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.error)
            return
        }
        request.httpBody = data
        transport.send(request) { result in
            if case .failure(let error) = result, (error as? URLError)?.code == .timedOut {
                completion(.timeout)
                return
            }
            guard case let .success((data, status)) = result, status == 200,
                  let reply = openAI
                    ? (try? JSONDecoder().decode(OpenAIResponse.self, from: data))?.choices.first?.message.content
                    : (try? JSONDecoder().decode(Response.self, from: data))?.text else {
                completion(.error)
                return
            }
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(text.isEmpty ? .error : .reply(text))
        }
    }

    private struct Response: Decodable {
        var text: String
    }

    private struct OpenAIResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String }
            var message: Message
        }
        var choices: [Choice]
    }
}

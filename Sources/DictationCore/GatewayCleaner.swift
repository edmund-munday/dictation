import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GatewayConfig: Codable, Equatable, Sendable {
    public var url: URL
    public var model: String
    public var key: String
    public var timeoutSeconds: Double

    public static let defaultModel = "deepseek/deepseek-flash"

    public init(url: URL, model: String = GatewayConfig.defaultModel, key: String, timeoutSeconds: Double = 3) {
        self.url = url
        self.model = model
        self.key = key
        self.timeoutSeconds = timeoutSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case url, model, key, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(URL.self, forKey: .url)
        key = try values.decode(String.self, forKey: .key)
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        timeoutSeconds = try values.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 3
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
            && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    public init(config: GatewayConfig, transport: GatewayHTTPTransport = URLSessionGatewayTransport()) {
        self.config = config
        self.transport = transport
    }

    public func clean(_ raw: String, completion: @escaping (String?) -> Void) {
        guard config.isValid else {
            completion(nil)
            return
        }
        var request = URLRequest(url: config.url.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": CleanupPrompt.text],
                ["role": "user", "content": SpokenMarkup.tokenize(raw)],
            ],
            "max_output_tokens": 600,
            "timeout_ms": Int(config.timeoutSeconds * 1_000),
            "tool_tag": "dictation:cleanup",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }
        request.httpBody = data
        transport.send(request) { result in
            guard case let .success((data, status)) = result, status == 200,
                  let response = try? JSONDecoder().decode(Response.self, from: data) else {
                completion(nil)
                return
            }
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(text.isEmpty ? nil : text)
        }
    }

    private struct Response: Decodable {
        var text: String
    }
}

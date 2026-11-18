import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case badStatus(Int, String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "地址无效"
        case .badStatus(let code, let body):
            if let body, !body.isEmpty { return "HTTP \(code)：\(body.prefix(120))" }
            return "HTTP \(code)"
        case .decoding(let detail): return "解析失败：\(detail)"
        case .transport(let detail): return "网络错误：\(detail)"
        }
    }
}

struct HttpRequest {
    var method: String = "GET"
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 20
    var retries: Int = 1

    static func get(_ url: URL, headers: [String: String] = [:]) -> HttpRequest {
        HttpRequest(method: "GET", url: url, headers: headers)
    }

    static func post<T: Encodable>(_ url: URL, json: T, headers: [String: String] = [:]) -> HttpRequest {
        var req = HttpRequest(method: "POST", url: url, headers: headers)
        req.body = try? JSONEncoder().encode(json)
        req.headers["Content-Type"] = "application/json"
        return req
    }
}

final class HttpClient {
    static let shared = HttpClient()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": LuUserAgent.value]
        config.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
        session = URLSession(configuration: config)
    }

    func send(_ request: HttpRequest) async throws -> Data {
        var attempt = 0
        var lastError: Error?

        while attempt <= max(0, request.retries) {
            attempt += 1
            do {
                var urlRequest = URLRequest(url: request.url,
                                            cachePolicy: .useProtocolCachePolicy,
                                            timeoutInterval: request.timeout)
                urlRequest.httpMethod = request.method
                urlRequest.httpBody = request.body
                urlRequest.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")
                request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.transport("非 HTTP 响应")
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw NetworkError.badStatus(http.statusCode,
                                                 String(data: data, encoding: .utf8))
                }
                return data
            } catch let error as NetworkError {
                lastError = error
                // 4xx 不重试
                if case .badStatus(let code, _) = error, (400..<500).contains(code) { throw error }
            } catch {
                lastError = NetworkError.transport(error.localizedDescription)
            }
            if attempt <= request.retries {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw lastError ?? NetworkError.transport("未知错误")
    }

    func json<T: Decodable>(_ request: HttpRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw NetworkError.decoding("\(error.localizedDescription) | \(snippet)")
        }
    }
}

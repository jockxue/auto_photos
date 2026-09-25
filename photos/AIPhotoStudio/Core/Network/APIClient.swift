import Foundation

enum HTTPMethod: String, CaseIterable, Sendable {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
}

enum APIEnvironment: String, Sendable {
    case development, staging, production
}

struct APIConfiguration: Sendable {
    let environment: APIEnvironment
    let baseURL: URL
    let apiKey: String?

    init(environment: APIEnvironment, baseURL: URL, apiKey: String? = nil) {
        self.environment = environment
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    static func fromEnvironment(
        _ environment: APIEnvironment,
        values: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> APIConfiguration {
        guard let rawURL = values["AI_API_BASE_URL"], let url = URL(string: rawURL) else {
            throw NetworkError.invalidConfiguration
        }
        return APIConfiguration(environment: environment, baseURL: url, apiKey: values["AI_API_KEY"])
    }
}

protocol TokenProvider: Sendable {
    func token() async throws -> String?
}

struct EmptyTokenProvider: TokenProvider {
    func token() async throws -> String? { nil }
}

struct EmptyRequestBody: Encodable, Sendable {}

struct APIRequest<Body: Encodable & Sendable>: Sendable {
    let method: HTTPMethod
    let path: String
    let query: [URLQueryItem]
    let body: Body?
    let headers: [String: String]

    init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Body? = nil,
        headers: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.headers = headers
    }
}

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (data, http)
    }
}

enum NetworkError: LocalizedError, Sendable {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case transport
    case httpStatus(Int)
    case decoding
    case encoding
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Network configuration is missing or invalid."
        case .invalidURL: "The request URL is invalid."
        case .invalidResponse: "The server response is invalid."
        case .transport: "The network request failed."
        case .httpStatus(let status): "The server returned HTTP \(status)."
        case .decoding: "The response could not be decoded."
        case .encoding: "The request could not be encoded."
        case .cancelled: "The request was cancelled."
        }
    }
}

enum AuthenticationError: LocalizedError, Sendable {
    case missingCredentials, unauthorized
    var errorDescription: String? { "Authentication is unavailable." }
}

enum UploadError: LocalizedError, Sendable {
    case sourceMissing, rejected
    var errorDescription: String? { "Upload failed." }
}

enum DownloadError: LocalizedError, Sendable {
    case invalidDestination, failed
    var errorDescription: String? { "Download failed." }
}

struct APIClient: Sendable {
    let configuration: APIConfiguration
    let tokenProvider: any TokenProvider
    let transport: any HTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: APIConfiguration,
        tokenProvider: any TokenProvider = EmptyTokenProvider(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: APIRequest<Body>,
        response: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        ) else { throw NetworkError.invalidURL }
        components.queryItems = request.query.isEmpty ? nil : request.query
        guard let url = components.url else { throw NetworkError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        if let apiKey = configuration.apiKey {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        if let token = try await tokenProvider.token() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            do {
                urlRequest.httpBody = try encoder.encode(body)
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw NetworkError.encoding
            }
        }
        do {
            let (data, http) = try await transport.data(for: urlRequest)
            guard 200..<300 ~= http.statusCode else {
                throw NetworkError.httpStatus(http.statusCode)
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw NetworkError.decoding
            }
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport
        }
    }
}

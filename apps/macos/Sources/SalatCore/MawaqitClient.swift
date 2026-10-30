import Foundation
import MawaKit

/// Abstraction over `URLSession` so the client can be tested without the network.
public protocol HTTPDataLoading: Sendable {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {
    public func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

public enum MawaqitError: LocalizedError, Equatable {
    case invalidLink
    case mosqueNotFound
    case unreadablePage
    case invalidCredentials
    case sessionExpired
    case rateLimited
    case server(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLink:
            "That doesn't look like a Mawaqit mosque link."
        case .mosqueNotFound:
            "No mosque was found at that address."
        case .unreadablePage:
            "The mosque page couldn't be read. Mawaqit may have changed its format."
        case .invalidCredentials:
            "Wrong email or password."
        case .sessionExpired:
            "Your Mawaqit session has expired. Please sign in again."
        case .rateLimited:
            "Too many requests. Please try again later."
        case let .server(code):
            "Mawaqit responded with an error (\(code))."
        }
    }
}

/// Talks to mawaqit.net.
///
/// Prayer times come from the public mosque page and need no account. Searching for
/// mosques uses the JSON API, which requires the token of a (free) Mawaqit account.
public struct MawaqitClient: Sendable {
    public static let baseURL = URL(string: "https://mawaqit.net")!
    static let userAgent = "SalatWidget/1.0 (Macintosh; macOS)"

    private let loader: any HTTPDataLoading
    private let now: @Sendable () -> Date

    public init(loader: any HTTPDataLoading = URLSession.shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.loader = loader
        self.now = now
    }

    public static func pageURL(for slug: String) -> URL {
        baseURL.appending(path: "en").appending(path: slug)
    }

    // MARK: - Prayer times

    public func fetchTimetable(slug: String) async throws -> Timetable {
        var request = URLRequest(url: Self.pageURL(for: slug))
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await send(request, notFound: .mosqueNotFound)

        guard let html = String(data: data, encoding: .utf8) else { throw MawaqitError.unreadablePage }
        do {
            let json = try ConfDataExtractor.extractJSON(from: html)
            let configuration = try JSONDecoder().decode(MosqueConfiguration.self, from: json)
            return Timetable(slug: slug, configuration: configuration, fetchedAt: now())
        } catch {
            throw MawaqitError.unreadablePage
        }
    }

    // MARK: - Account & search

    /// Exchanges Mawaqit account credentials for an API token. The password is only
    /// sent to Mawaqit over HTTPS and is never stored.
    public func signIn(email: String, password: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appending(path: "api/2.0/me"))
        let credentials = Data("\(email):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            data = try await send(request)
        } catch MawaqitError.sessionExpired {
            throw MawaqitError.invalidCredentials
        }

        struct Account: Decodable { let apiAccessToken: String }
        guard let token = try? JSONDecoder().decode(Account.self, from: data).apiAccessToken,
              !token.isEmpty
        else { throw MawaqitError.invalidCredentials }
        return token
    }

    public func searchMosques(_ query: String, token: String, limit: Int = 20) async throws -> [MosqueSearchResult] {
        let word = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard word.count >= 2 else { return [] }

        let search = mosqueSearchByNameRequest(word: word, token: token)
        var request = URLRequest(url: URL(string: search.url)!)
        for header in search.headers { request.setValue(header.value, forHTTPHeaderField: header.name) }

        let data = try await send(request)
        do {
            return try parseMosqueSearchResults(body: String(decoding: data, as: UTF8.self))
        } catch {
            throw MawaqitError.unreadablePage
        }
    }

    // MARK: - Transport

    private func send(_ request: URLRequest, notFound: MawaqitError = .server(statusCode: 404)) async throws -> Data {
        var request = request
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await loader.load(request)
        guard let http = response as? HTTPURLResponse else { throw MawaqitError.server(statusCode: -1) }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw MawaqitError.sessionExpired
        case 404: throw notFound
        case 429: throw MawaqitError.rateLimited
        default: throw MawaqitError.server(statusCode: http.statusCode)
        }
    }
}

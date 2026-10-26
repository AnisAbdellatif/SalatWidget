import Foundation
import Testing
@testable import SalatCore

enum Fixture {
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    static var html: String {
        get throws {
            let url = try #require(Bundle.module.url(forResource: "assunna-hannover", withExtension: "html", subdirectory: "Fixtures"))
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    static var configuration: MosqueConfiguration {
        get throws {
            let json = try ConfDataExtractor.extractJSON(from: html)
            return try JSONDecoder().decode(MosqueConfiguration.self, from: json)
        }
    }

    /// The fixture was captured on Friday, 23 October 2026.
    static func timetable(fetchedAt: Date = date(2026, 10, 23, 10, 0)) throws -> Timetable {
        Timetable(slug: "assunna-hannover", configuration: try configuration, fetchedAt: fetchedAt)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}

/// Serves canned responses and records the requests it receives.
final class MockLoader: HTTPDataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) -> (Int, Data)

    init(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

import Foundation
import Testing
@testable import SalatCore

@Suite("Mawaqit client")
struct MawaqitClientTests {
    @Test func fetchesTimetableFromMosquePage() async throws {
        let html = try Fixture.html
        let fetchedAt = Fixture.date(2026, 10, 23, 9, 30)
        let loader = MockLoader { _ in (200, Data(html.utf8)) }
        let client = MawaqitClient(loader: loader, now: { fetchedAt })

        let timetable = try await client.fetchTimetable(slug: "assunna-hannover")

        #expect(timetable.slug == "assunna-hannover")
        #expect(timetable.fetchedAt == fetchedAt)
        #expect(timetable.timeZone == Fixture.berlin)
        let request = try #require(loader.requests.first)
        #expect(request.url?.absoluteString == "https://mawaqit.net/en/assunna-hannover")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("SalatWidget/") == true)
    }

    @Test func mapsMissingMosqueTo404() async {
        let client = MawaqitClient(loader: MockLoader { _ in (404, Data()) })
        await #expect(throws: MawaqitError.mosqueNotFound) {
            try await client.fetchTimetable(slug: "nope")
        }
    }

    @Test func reportsPagesWithoutConfData() async {
        let client = MawaqitClient(loader: MockLoader { _ in (200, Data("<html></html>".utf8)) })
        await #expect(throws: MawaqitError.unreadablePage) {
            try await client.fetchTimetable(slug: "x")
        }
    }

    @Test func signsInWithBasicAuth() async throws {
        let loader = MockLoader { _ in (200, Data(#"{"apiAccessToken":"tok-123","email":"a@b.c"}"#.utf8)) }
        let token = try await MawaqitClient(loader: loader).signIn(email: "a@b.c", password: "pw")

        #expect(token == "tok-123")
        let request = try #require(loader.requests.first)
        #expect(request.url?.path() == "/api/2.0/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("a@b.c:pw".utf8).base64EncodedString())
    }

    @Test func rejectsWrongCredentials() async {
        let client = MawaqitClient(loader: MockLoader { _ in (401, Data(#"{"code":401}"#.utf8)) })
        await #expect(throws: MawaqitError.invalidCredentials) {
            try await client.signIn(email: "a@b.c", password: "wrong")
        }
    }

    @Test func searchesWithToken() async throws {
        let body = #"""
        [{"uuid":"8b5e72c0","name":"Assunna","label":"Masjid Assunna - Hannover","slug":"assunna-hannover",
          "localisation":"Hannover, Germany","type":"MOSQUE","latitude":52.3,"longitude":9.7},
         {"uuid":"aa","name":"Home","label":null,"slug":null,"localisation":null}]
        """#
        let loader = MockLoader { _ in (200, Data(body.utf8)) }
        let results = try await MawaqitClient(loader: loader).searchMosques("  hannover ", token: "tok")

        #expect(results.count == 2)
        #expect(results[0].displayName == "Masjid Assunna - Hannover")
        #expect(results[0].slug == "assunna-hannover")
        #expect(results[1].displayName == "Home")

        let request = try #require(loader.requests.first)
        #expect(request.value(forHTTPHeaderField: "Api-Access-Token") == "tok")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "word", value: "hannover")))
    }

    @Test func skipsTooShortSearches() async throws {
        let loader = MockLoader { _ in (200, Data("[]".utf8)) }
        #expect(try await MawaqitClient(loader: loader).searchMosques("a", token: "t").isEmpty)
        #expect(loader.requests.isEmpty)
    }

    @Test func reportsExpiredToken() async {
        let client = MawaqitClient(loader: MockLoader { _ in (401, Data()) })
        await #expect(throws: MawaqitError.sessionExpired) {
            try await client.searchMosques("paris", token: "old")
        }
    }
}

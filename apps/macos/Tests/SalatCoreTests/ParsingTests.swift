import Foundation
import Testing
@testable import SalatCore

@Suite("Parsing")
struct ParsingTests {
    @Test func extractsConfDataFromMosquePage() throws {
        let configuration = try Fixture.configuration
        #expect(configuration.name.hasSuffix("Hannover"))
        #expect(configuration.timezone == "Europe/Berlin")
        #expect(configuration.calendar.count == 12)
        #expect(configuration.iqamaCalendar.count == 12)
        #expect(configuration.times == ["06:15", "13:07", "15:41", "18:14", "19:44"])
        #expect(configuration.jumua == "13:20")
        #expect(configuration.iqamaEnabled)
    }

    @Test func ignoresBracesInsideStrings() throws {
        let html = #"<script>var confData = {"name": "A } { \"quoted\" }", "calendar": []};</script>"#
        let data = try ConfDataExtractor.extractJSON(from: html)
        let configuration = try JSONDecoder().decode(MosqueConfiguration.self, from: data)
        #expect(configuration.name == #"A } { "quoted" }"#)
    }

    @Test func skipsMentionsThatAreNotAssignments() throws {
        let html = #"<script>log(confData); var confData={"name":"B","calendar":[]};</script>"#
        let data = try ConfDataExtractor.extractJSON(from: html)
        #expect(try JSONDecoder().decode(MosqueConfiguration.self, from: data).name == "B")
    }

    @Test func reportsMissingConfData() {
        #expect(throws: ConfDataExtractor.Failure.notFound) {
            try ConfDataExtractor.extractJSON(from: "<html>No data</html>")
        }
        #expect(throws: ConfDataExtractor.Failure.unterminated) {
            try ConfDataExtractor.extractJSON(from: #"confData = {"name": "x""#)
        }
    }

    @Test func decodesLeniently() throws {
        let json = #"{"name":"X","calendar":[],"hijriAdjustment":"-1","iqamaEnabled":null,"jumua":5}"#
        let configuration = try JSONDecoder().decode(MosqueConfiguration.self, from: Data(json.utf8))
        #expect(configuration.hijriAdjustment == -1)
        #expect(configuration.iqamaEnabled)
        #expect(configuration.jumua == nil)
        #expect(configuration.iqamaCalendar.isEmpty)
    }

    @Test func prefersLabelForDisplayName() {
        var configuration = MosqueConfiguration(name: "Name", calendar: [])
        #expect(configuration.displayName == "Name")
        configuration.label = "  Label "
        #expect(configuration.displayName == "Label")
    }

    @Test(arguments: [
        ("https://mawaqit.net/de/assunna-hannover", "assunna-hannover"),
        ("mawaqit.net/en/w/assunna-hannover?showOnly5PrayerTimes=0", "assunna-hannover"),
        ("https://www.mawaqit.net/fr/m/grande-mosquee-de-paris/", "grande-mosquee-de-paris"),
        ("  Assunna-Hannover  ", "assunna-hannover"),
    ])
    func parsesMosqueLinks(input: String, expected: String) {
        #expect(MosqueLink.slug(from: input) == expected)
    }

    @Test(arguments: ["", "https://example.com/de/assunna-hannover", "two words", "https://mawaqit.net/", "x"])
    func rejectsInvalidLinks(input: String) {
        #expect(MosqueLink.slug(from: input) == nil)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test(arguments: [
        (0.0, "0s"), (0.4, "1s"), (59.0, "59s"), (59.5, "1m"), (60.0, "1m"), (61.0, "2m"),
        (3600.0, "1h"), (3601.0, "1h 1m"), (5000.0, "1h 24m"),
    ])
    func compactCountdown(interval: TimeInterval, expected: String) {
        #expect(CountdownFormatter.compact(interval) == expected)
    }

    @Test func predictsWhenTheCompactCountdownChanges() {
        let samples: [TimeInterval] = [0.3, 1, 5.3, 58.7, 59, 59.5, 60, 60.5, 61, 119.9, 120, 3599, 3600, 3600.5, 5000, 20_000.25]
        for remaining in samples {
            let wait = CountdownFormatter.timeUntilCompactChange(remaining)
            let shown = CountdownFormatter.compact(remaining)
            #expect(wait > 0, "remaining \(remaining)")
            // Unchanged for the whole wait…
            #expect(CountdownFormatter.compact(remaining - wait + 0.001) == shown, "remaining \(remaining)")
            // …and different the moment it ends.
            #expect(CountdownFormatter.compact(remaining - wait) != shown, "remaining \(remaining)")
        }
        #expect(CountdownFormatter.timeUntilCompactChange(5000) == 20)
        #expect(CountdownFormatter.timeUntilCompactChange(0) == 0)
    }

    @Test func clockCountdown() {
        #expect(CountdownFormatter.clock(5) == "0:05")
        #expect(CountdownFormatter.clock(754) == "12:34")
        #expect(CountdownFormatter.clock(5025) == "1:23:45")
    }

    @Test func hijriDateAppliesAdjustment() {
        let locale = Locale(identifier: "en_US")
        let day = Fixture.date(2026, 10, 23, 12, 0)
        let base = HijriDate.string(for: day, timeZone: Fixture.berlin, locale: locale)
        let shifted = HijriDate.string(for: day, adjustment: 1, timeZone: Fixture.berlin, locale: locale)
        #expect(base.contains("1448"))
        #expect(base != shifted)
    }
}

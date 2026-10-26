import Foundation

/// The subset of a mosque's Mawaqit configuration (`confData`) that the app uses.
///
/// Decoding is deliberately lenient: Mawaqit omits or nulls many fields depending on
/// how a mosque is set up, so only the name and the yearly calendar are required.
public struct MosqueConfiguration: Codable, Sendable, Equatable {
    public var name: String
    public var label: String?
    /// IANA identifier, e.g. `Europe/Berlin`.
    public var timezone: String?
    public var url: String?
    public var iqamaEnabled: Bool
    public var jumua: String?
    public var jumua2: String?
    public var jumua3: String?
    /// When true, Jumu'a is held at the regular Dhuhr time.
    public var jumuaAsDuhr: Bool
    public var hijriAdjustment: Int
    /// Today's five prayer times (Fajr, Dhuhr, Asr, Maghrib, Isha) as computed by
    /// Mawaqit on the day the page was fetched. These include any manual adjustments.
    public var times: [String]?
    /// Today's sunrise, matching `times`.
    public var shuruq: String?
    /// Twelve months, each mapping a day number (`"1"`…`"31"`) to six times:
    /// Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha, in local wall-clock time.
    public var calendar: [[String: [String]]]
    /// Twelve months, each mapping a day number to five iqama rules (one per
    /// obligatory prayer): either an offset such as `"+10"` or a time such as `"13:00"`.
    public var iqamaCalendar: [[String: [String]]]

    public var displayName: String {
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    public init(
        name: String,
        label: String? = nil,
        timezone: String? = nil,
        url: String? = nil,
        iqamaEnabled: Bool = true,
        jumua: String? = nil,
        jumua2: String? = nil,
        jumua3: String? = nil,
        jumuaAsDuhr: Bool = false,
        hijriAdjustment: Int = 0,
        times: [String]? = nil,
        shuruq: String? = nil,
        calendar: [[String: [String]]],
        iqamaCalendar: [[String: [String]]] = []
    ) {
        self.name = name
        self.label = label
        self.timezone = timezone
        self.url = url
        self.iqamaEnabled = iqamaEnabled
        self.jumua = jumua
        self.jumua2 = jumua2
        self.jumua3 = jumua3
        self.jumuaAsDuhr = jumuaAsDuhr
        self.hijriAdjustment = hijriAdjustment
        self.times = times
        self.shuruq = shuruq
        self.calendar = calendar
        self.iqamaCalendar = iqamaCalendar
    }

    private enum CodingKeys: String, CodingKey {
        case name, label, timezone, url, iqamaEnabled, jumua, jumua2, jumua3
        case jumuaAsDuhr, hijriAdjustment, times, shuruq, calendar, iqamaCalendar
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        calendar = try c.decode([[String: [String]]].self, forKey: .calendar)

        label = c.lenient(String.self, .label)
        timezone = c.lenient(String.self, .timezone)
        url = c.lenient(String.self, .url)
        iqamaEnabled = c.lenient(Bool.self, .iqamaEnabled) ?? true
        jumua = c.lenient(String.self, .jumua)
        jumua2 = c.lenient(String.self, .jumua2)
        jumua3 = c.lenient(String.self, .jumua3)
        jumuaAsDuhr = c.lenient(Bool.self, .jumuaAsDuhr) ?? false
        hijriAdjustment = c.lenient(Int.self, .hijriAdjustment)
            ?? c.lenient(String.self, .hijriAdjustment).flatMap { Int($0) }
            ?? 0
        times = c.lenient([String].self, .times)
        shuruq = c.lenient(String.self, .shuruq)
        iqamaCalendar = c.lenient([[String: [String]]].self, .iqamaCalendar) ?? []
    }
}

private extension KeyedDecodingContainer {
    /// Decodes an optional value, treating a type mismatch like a missing key.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// A mosque's configuration together with where and when it was fetched.
public struct Timetable: Codable, Sendable, Equatable {
    /// The mosque's identifier in its Mawaqit URL, e.g. `assunna-hannover`.
    public var slug: String
    public var configuration: MosqueConfiguration
    public var fetchedAt: Date

    public init(slug: String, configuration: MosqueConfiguration, fetchedAt: Date) {
        self.slug = slug
        self.configuration = configuration
        self.fetchedAt = fetchedAt
    }

    public var timeZone: TimeZone {
        configuration.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    public var pageURL: URL {
        MawaqitClient.pageURL(for: slug)
    }
}

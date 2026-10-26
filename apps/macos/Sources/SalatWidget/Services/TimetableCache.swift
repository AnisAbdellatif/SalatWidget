import Foundation
import SalatCore
import OSLog

/// Keeps the last downloaded timetable on disk so the app works offline and shows
/// times instantly at launch. A timetable covers the whole year, so a stale copy is
/// still useful for days.
struct TimetableCache: Sendable {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "SalatWidget", directoryHint: .isDirectory)
        fileURL = base.appending(path: "timetable.json")
    }

    func load() -> Timetable? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(Timetable.self, from: data)
        } catch {
            Logger.app.error("Discarding unreadable cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ timetable: Timetable) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(timetable).write(to: fileURL, options: .atomic)
        } catch {
            Logger.app.error("Failed to cache timetable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SalatWidget", category: "app")
}

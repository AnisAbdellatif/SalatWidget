import Foundation

/// Pulls the `confData` JSON object out of a Mawaqit mosque page (via MawaKit).
public enum ConfDataExtractor {
    public enum Failure: Error, Equatable {
        case notFound
        case unterminated
    }

    public static func extractJSON(from html: String) throws -> Data {
        do {
            return Data(try extractConfData(html: html).utf8)
        } catch MawaKitError.ConfDataUnterminated {
            throw Failure.unterminated
        } catch {
            throw Failure.notFound
        }
    }
}

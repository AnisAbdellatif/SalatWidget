import Foundation

/// Turns what a user pastes (a Mawaqit URL or a bare slug) into a mosque slug (via MawaKit).
public enum MosqueLink {
    public static func slug(from input: String) -> String? {
        mosqueSlug(input: input)
    }
}

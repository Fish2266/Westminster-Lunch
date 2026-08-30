import Foundation

/// A single food item within a category, e.g. "Chicken Tenders".
///
/// Deliberately not `Identifiable`: the only candidate identity is the name,
/// and Flik makes no promise that item names are unique within a category. The
/// views iterate items by position instead, so a repeated name still renders.
struct MenuItem: Codable, Equatable, Hashable {
    let name: String
    let description: String?
}

/// A category of items as Flik/Nutrislice organizes them, e.g. "Entrees", "Sides".
/// Categories and their order are entirely dynamic — nothing here is hardcoded.
struct MenuCategory: Codable, Equatable, Identifiable, Hashable {
    /// Safe as an identity, unlike `MenuItem`'s name: `MenuService` folds all
    /// items sharing a section title into one category, so the names of the
    /// categories in a `DayMenu` are unique by construction.
    var id: String { name }
    let name: String
    let items: [MenuItem]
}

/// The fully-resolved menu for one dining location on one day, ready for display.
struct DayMenu: Codable, Equatable {
    let locationSlug: String
    let date: Date
    let categories: [MenuCategory]
    /// When this data was retrieved from the network (used for "Updated at" and
    /// for deciding whether cached data is fresh enough to skip a widget refetch).
    let fetchedAt: Date

    var isEmpty: Bool {
        categories.allSatisfy { $0.items.isEmpty }
    }
}

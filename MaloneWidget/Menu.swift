import Foundation

/// A single food item within a category, e.g. "Chicken Tenders".
struct MenuItem: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String?
}

/// A category of items as Flik/Nutrislice organizes them, e.g. "Entrees", "Sides".
/// Categories and their order are entirely dynamic — nothing here is hardcoded.
struct MenuCategory: Codable, Equatable, Identifiable, Hashable {
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

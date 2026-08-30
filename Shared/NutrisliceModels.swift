import Foundation

/// Raw decoding targets for Nutrislice's week-menu JSON response. Field names here
/// follow the shape documented by long-standing community integrations against the
/// public Nutrislice API (e.g. MMM-Nutrislice, Home Assistant REST sensors):
///
/// {
///   "days": [
///     {
///       "date": "2026-08-17",
///       "menu_items": [
///         { "is_section_title": true, "text": "Entrees" },
///         { "food": { "name": "Chicken Tenders", "description": "..." } },
///         { "food": { "name": "Rice", "description": null } },
///         { "is_section_title": true, "text": "Dessert" },
///         { "food": { "name": "Fruit Cup", "description": null } }
///       ]
///     },
///     ...
///   ]
/// }
///
/// All fields are optional/defensive where reasonable, since real-world Nutrislice
/// payloads sometimes omit fields or include entry types (station headers, images,
/// text-only announcements) beyond plain food items and section titles. Anything
/// MenuService doesn't recognize is simply skipped rather than causing a decode
/// failure for the whole day.
struct NutrisliceWeekResponse: Decodable {
    let days: [NutrisliceDay]
}

struct NutrisliceDay: Decodable {
    /// "yyyy-MM-dd"
    let date: String
    let menuItems: [NutrisliceMenuItem]
}

struct NutrisliceMenuItem: Decodable {
    let isSectionTitle: Bool?
    /// Present when isSectionTitle == true; the category header text (e.g. "Entrees").
    let text: String?
    /// Present for actual food rows.
    let food: NutrisliceFood?
}

struct NutrisliceFood: Decodable {
    let name: String
    let description: String?
}

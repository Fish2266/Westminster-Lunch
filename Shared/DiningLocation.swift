import Foundation

/// Represents a Flik / Nutrislice dining location ("school" in Nutrislice's data model).
///
/// Values below were confirmed directly from a Safari Web Inspector Network-tab
/// capture of https://westminster.flikisdining.com/menu on 2026-08-17/18 — not
/// guessed. Notably, the slug behind the "Hawkins" menu in Flik's UI is internally
/// named "campbell" (both the school slug and the menu-type slug), not "hawkins" —
/// confirming it was worth verifying rather than assuming.
///
/// Captured requests:
///   Hawkins → https://westminster.api.flikisdining.com/menu/api/weeks/school/campbell/menu-type/campbell/2026/08/17/
///   Malone  → https://westminster.api.flikisdining.com/menu/api/weeks/school/uppermiddle-school-malone-dining-hall/menu-type/lunch/2026/08/17/
///
/// Both returned HTTP 200 with `Content-Type: application/json`, no auth/API key.
/// The only header that turned out to matter is a browser-like `User-Agent` —
/// see `MenuService.fetchWeekFromNetwork` for why.
struct DiningLocation: Identifiable, Codable, Equatable, Hashable {
    /// The Nutrislice "school slug" for this dining hall.
    let schoolSlug: String
    /// The Nutrislice "menu-type slug" for lunch at this hall.
    let menuTypeSlug: String
    /// Human-readable name shown in the UI.
    let displayName: String
    /// SF Symbol used in the UI.
    let symbolName: String
    /// Optional display order for category names, e.g. ["Sandwich #1", "Sandwich #2"].
    /// Categories listed here are shown first, in this exact order. Any category
    /// Flik returns that ISN'T listed here still shows up — just after all the
    /// listed ones, in whatever order Flik itself returned it. This means adding
    /// a new Flik category never hides it; it just falls through to the end
    /// until you decide to prioritize it explicitly.
    let preferredCategoryOrder: [String]

    var id: String { schoolSlug }

    static let hawkins = DiningLocation(
        schoolSlug: "campbell",
        menuTypeSlug: "campbell",
        displayName: "Hawkins",
        symbolName: "cup.and.saucer.fill",
        preferredCategoryOrder: ["Sandwich #1", "Sandwich #2", "Vegetarian Sandwich"]
    )

    static let malone = DiningLocation(
        schoolSlug: "uppermiddle-school-malone-dining-hall",
        menuTypeSlug: "lunch",
        displayName: "Malone",
        symbolName: "fork.knife",
        preferredCategoryOrder: []
    )

    /// All locations shown on the home screen. Add more here as additional
    /// Flik/Nutrislice slugs are confirmed — nothing else in the app needs to change.
    static let all: [DiningLocation] = [.hawkins, .malone]

    static func location(forSchoolSlug slug: String) -> DiningLocation? {
        all.first { $0.schoolSlug == slug }
    }
}

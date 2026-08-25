import Foundation

/// Persists the most recently fetched menu per (dining location, day) in the
/// shared App Group container, so both the watch app and the widget extension
/// can read the last successfully downloaded menu without needing their own
/// network call. Keyed by date as well as location so that swiping through
/// past/future days in the app never overwrites the cache entry the widget
/// relies on for today.
///
///   Flik server → MenuService → MenuCache (App Group) → Watch app UI
///                                                     ↘ Malone Widget
struct MenuCache {
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    private func key(for location: DiningLocation, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dateString = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        return "cached_menu_\(location.schoolSlug)_\(dateString)"
    }

    /// Saves under the menu's own `date` field, so callers never need to pass
    /// the date separately from the data being saved.
    func save(_ menu: DayMenu, for location: DiningLocation) {
        guard let defaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(menu) else { return }
        defaults.set(data, forKey: key(for: location, date: menu.date))
    }

    func load(for location: DiningLocation, date: Date = Date()) -> DayMenu? {
        guard let defaults, let data = defaults.data(forKey: key(for: location, date: date)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DayMenu.self, from: data)
    }
}

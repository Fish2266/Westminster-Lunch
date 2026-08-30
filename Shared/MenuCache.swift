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

    private func keyPrefix(for location: DiningLocation) -> String {
        "cached_menu_\(location.schoolSlug)_"
    }

    private func key(for location: DiningLocation, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dateString = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        return keyPrefix(for: location) + dateString
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
        return decode(data)
    }

    /// The newest cached menu for a location, regardless of which day it's for.
    ///
    /// The widget uses this as a last resort: on a real watch a timeline refresh
    /// can easily land before today's menu has ever been fetched (no network on
    /// the wrist, or the app hasn't been opened yet today). Showing yesterday's
    /// items, clearly dated, beats rendering an empty widget — which is what the
    /// day-keyed `load(for:date:)` alone would produce.
    func loadMostRecent(for location: DiningLocation) -> DayMenu? {
        guard let defaults else { return nil }
        let prefix = keyPrefix(for: location)
        return defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .compactMap { defaults.data(forKey: $0) }
            .compactMap(decode)
            .max(by: { $0.date < $1.date })
    }

    private func decode(_ data: Data) -> DayMenu? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DayMenu.self, from: data)
    }
}

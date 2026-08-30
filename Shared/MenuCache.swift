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
    /// How far back cached days are kept. Nothing in the app ever looks further
    /// back than a week or two, and the widget's `loadMostRecent(for:)` has to
    /// scan whatever is here, so letting every day the person ever swiped past
    /// accumulate in the App Group container would only slow it down.
    private static let retentionDays = 30

    private let defaults: UserDefaults?

    /// The default is the shared App Group container — the only thing production
    /// ever uses. The parameter exists so tests can hand in a throwaway suite
    /// instead of reading and pruning the real cache.
    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        self.defaults = defaults
    }

    private func keyPrefix(for location: DiningLocation) -> String {
        "cached_menu_\(location.schoolSlug)_"
    }

    private func key(for location: DiningLocation, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dateString = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        return keyPrefix(for: location) + dateString
    }

    /// The day a key was written for, recovered from the key itself. Lets the
    /// prune and most-recent scans order entries without decoding every blob.
    private func day(fromKey key: String, prefix: String) -> Date? {
        let parts = key.dropFirst(prefix.count).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        return Calendar.current.date(from: components)
    }

    private func cachedKeys(for location: DiningLocation, in defaults: UserDefaults) -> [(key: String, date: Date)] {
        let prefix = keyPrefix(for: location)
        return defaults.dictionaryRepresentation().keys
            .compactMap { key -> (key: String, date: Date)? in
                guard key.hasPrefix(prefix), let date = day(fromKey: key, prefix: prefix) else { return nil }
                return (key: key, date: date)
            }
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
    ///
    /// Keys are sorted by their own encoded day and decoded newest-first, so the
    /// usual case reads exactly one blob rather than all of them — this runs
    /// inside the widget's very short timeline budget.
    func loadMostRecent(for location: DiningLocation) -> DayMenu? {
        guard let defaults else { return nil }
        for entry in cachedKeys(for: location, in: defaults).sorted(by: { $0.date > $1.date }) {
            if let data = defaults.data(forKey: entry.key), let menu = decode(data) {
                return menu
            }
        }
        return nil
    }

    /// Drops entries older than `retentionDays`. Called once after a whole
    /// week has been saved rather than from `save` itself, so a single fetch
    /// doesn't re-scan the container five times over.
    func pruneExpiredEntries(for location: DiningLocation) {
        guard let defaults else { return }
        let calendar = Calendar.current
        guard let cutoff = calendar.date(
            byAdding: .day,
            value: -Self.retentionDays,
            to: calendar.startOfDay(for: Date())
        ) else { return }

        for entry in cachedKeys(for: location, in: defaults) where entry.date < cutoff {
            defaults.removeObject(forKey: entry.key)
        }
    }

    private func decode(_ data: Data) -> DayMenu? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DayMenu.self, from: data)
    }
}

import Foundation

enum MenuServiceError: Error, LocalizedError, Equatable {
    case invalidURL
    case network(String)
    case decoding(String)
    case noDataForDate

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Couldn't build the menu request."
        case .network(let message):
            return "Network error: \(message)"
        case .decoding(let message):
            return "Couldn't read the menu data: \(message)"
        case .noDataForDate:
            return "No menu has been published for today yet."
        }
    }
}

/// Fetches, parses, and caches dining hall menus. Used identically by the watch
/// app and the widget extension — neither has any networking or parsing logic
/// of its own.
///
///   Flik server → MenuService.fetchWeekFromNetwork → MenuCache.save (every
///                                                    day in the week)
///                                                  ↘ requested day returned
///
/// An `actor` is used so concurrent calls from the app and widget (which run in
/// separate processes but share this type's source) can't race on the cache.
actor MenuService {
    static let shared = MenuService()

    private let session: URLSession
    private let cache = MenuCache()

    init(session: URLSession = MenuService.makeDefaultSession()) {
        self.session = session
    }

    /// A session with hard, short timeouts.
    ///
    /// This matters most in the widget extension: WidgetKit gives `getTimeline`
    /// only a few seconds of wall time on real hardware, and a watch whose radio
    /// is asleep or off-wrist can leave `URLSession.shared` (60s request timeout,
    /// and `waitsForConnectivity` behaviour that can stall indefinitely) hanging
    /// well past that budget. When that happens the extension is killed before it
    /// ever calls the timeline completion handler, and watchOS renders the widget
    /// as an empty black card — the exact symptom that never reproduces in the
    /// Simulator, where the request resolves instantly over the Mac's network.
    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Fetches today's (or `date`'s) menu for a location from the network.
    /// On any failure, falls back to the cached menu for that same calendar day
    /// if one exists, so the UI can still show something useful offline.
    func menu(for location: DiningLocation, date: Date = Date()) async -> Result<DayMenu, MenuServiceError> {
        do {
            let fresh = try await fetchDayCachingWholeWeek(location: location, date: date)
            return .success(fresh)
        } catch let error as MenuServiceError {
            if let cached = cache.load(for: location, date: date) {
                return .success(cached)
            }
            return .failure(error)
        } catch {
            if let cached = cache.load(for: location, date: date) {
                return .success(cached)
            }
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Returns cached data immediately, without touching the network. The widget
    /// prefers this so it doesn't spend the device's limited background refresh
    /// budget re-fetching data the app already downloaded recently.
    func cachedMenu(for location: DiningLocation, date: Date = Date()) -> DayMenu? {
        cache.load(for: location, date: date)
    }

    /// The newest cached menu for a location whatever day it belongs to — the
    /// widget's last resort so it can always render *something* rather than an
    /// empty card. See `MenuCache.loadMostRecent(for:)`.
    func mostRecentCachedMenu(for location: DiningLocation) -> DayMenu? {
        cache.loadMostRecent(for: location)
    }

    /// Makes sure the two days that always matter — the current school day and
    /// the next one — are sitting in the cache, fetching only what's missing or
    /// stale. Called on app launch and from the widget's timeline refresh, so
    /// that a watch with no network can still render both days.
    ///
    /// Because Nutrislice serves a whole week per request and
    /// `fetchDayCachingWholeWeek` caches every day of it, this is usually a
    /// single network call covering both days — two only when the next school
    /// day falls in the following week (i.e. on a Friday).
    @discardableResult
    func prefetchEssentials(for location: DiningLocation, now: Date = Date()) async -> Result<DayMenu, MenuServiceError> {
        var result: Result<DayMenu, MenuServiceError>?

        for day in SchoolCalendar.daysToKeepCached(from: now) {
            let cached = cache.load(for: location, date: day)
            if let cached, Calendar.current.isDate(cached.fetchedAt, inSameDayAs: now) {
                // Already downloaded today; lunch doesn't change once published.
                if result == nil { result = .success(cached) }
                continue
            }

            do {
                let fresh = try await fetchDayCachingWholeWeek(location: location, date: day)
                if result == nil { result = .success(fresh) }
            } catch {
                let failure: Result<DayMenu, MenuServiceError>
                if let cached {
                    failure = .success(cached)
                } else if let error = error as? MenuServiceError {
                    failure = .failure(error)
                } else {
                    failure = .failure(.network(error.localizedDescription))
                }
                if result == nil { result = failure }
            }
        }

        // The loop always runs at least once, so this fallback is unreachable
        // in practice — it just keeps the signature non-optional.
        return result ?? .failure(.noDataForDate)
    }

    /// Fetches the week containing `date` and caches **every** day in it, then
    /// returns the one for `date`. Caching the sibling days is free — the
    /// response already contains them — and it's what lets tomorrow's menu be
    /// available offline without a second request.
    private func fetchDayCachingWholeWeek(location: DiningLocation, date: Date) async throws -> DayMenu {
        let week = try await fetchWeekFromNetwork(location: location, date: date)
        for day in week {
            cache.save(day, for: location)
        }

        let calendar = Calendar.current
        guard let match = week.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
            throw MenuServiceError.noDataForDate
        }
        return match
    }

    /// Downloads the week containing `date` and turns every school day in it
    /// into a `DayMenu`. Weekend entries are dropped: no food is served, so
    /// nothing in the app ever needs them.
    private func fetchWeekFromNetwork(location: DiningLocation, date: Date) async throws -> [DayMenu] {
        guard let url = NutrisliceConfig.weekMenuURL(for: location, weekOf: date) else {
            throw MenuServiceError.invalidURL
        }

        // The server rejects requests whose User-Agent doesn't look like a real
        // browser (confirmed via live testing: identical requests returned 200
        // with a Safari User-Agent and 400 with URLSession's default CFNetwork
        // UA, with no other header differences). This is presumably a bot/WAF
        // filter in front of the Nutrislice deployment, not something documented
        // by Nutrislice itself, so it's included here defensively and may need
        // revisiting if the string below gets specifically blocklisted later.
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MenuServiceError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MenuServiceError.network("Server returned status \(http.statusCode).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let week: NutrisliceWeekResponse
        do {
            week = try decoder.decode(NutrisliceWeekResponse.self, from: data)
        } catch {
            throw MenuServiceError.decoding(error.localizedDescription)
        }

        let fetchedAt = Date()
        return week.days.compactMap { day in
            guard let dayDate = Self.dayFormatter.date(from: day.date),
                  SchoolCalendar.isSchoolDay(dayDate) else { return nil }
            return dayMenu(from: day, location: location, date: dayDate, fetchedAt: fetchedAt)
        }
    }

    /// Parses "yyyy-MM-dd" into local midnight, so a menu's `date` always lines
    /// up with the calendar day the rest of the app (and the cache key) uses.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }()

    private func dayMenu(from day: NutrisliceDay, location: DiningLocation, date: Date, fetchedAt: Date) -> DayMenu {
        // Group items under the most recent preceding section title, preserving
        // the order Flik returns them in. No category names or items are assumed
        // or hardcoded — whatever Flik provides is what gets displayed.
        var itemsByCategory: [String: [MenuItem]] = [:]
        var categoryOrder: [String] = []
        var currentCategory = "Menu"

        for entry in day.menuItems {
            if entry.isSectionTitle == true, let title = entry.text, !title.isEmpty {
                currentCategory = title
                if !categoryOrder.contains(currentCategory) {
                    categoryOrder.append(currentCategory)
                }
                continue
            }
            guard let food = entry.food, !food.name.isEmpty else { continue }
            if !categoryOrder.contains(currentCategory) {
                categoryOrder.append(currentCategory)
            }
            itemsByCategory[currentCategory, default: []].append(
                MenuItem(name: food.name, description: food.description)
            )
        }

        let categories: [MenuCategory] = categoryOrder.compactMap { name in
            guard let items = itemsByCategory[name], !items.isEmpty else { return nil }
            return MenuCategory(name: name, items: items)
        }

        return DayMenu(
            locationSlug: location.schoolSlug,
            date: Calendar.current.startOfDay(for: date),
            categories: sortCategories(categories, preferredOrder: location.preferredCategoryOrder),
            fetchedAt: fetchedAt
        )
    }

    /// Puts any category named in `preferredOrder` first, in that exact order.
    /// Everything else keeps its original relative order and is appended after.
    /// A category listed in `preferredOrder` but not present today is simply
    /// skipped — nothing crashes or shows a blank section.
    private func sortCategories(_ categories: [MenuCategory], preferredOrder: [String]) -> [MenuCategory] {
        guard !preferredOrder.isEmpty else { return categories }

        var remaining = categories
        var result: [MenuCategory] = []

        for name in preferredOrder {
            if let index = remaining.firstIndex(where: { $0.name == name }) {
                result.append(remaining.remove(at: index))
            }
        }

        result.append(contentsOf: remaining)
        return result
    }
}

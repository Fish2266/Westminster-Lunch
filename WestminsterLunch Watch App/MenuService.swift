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
///   Flik server → MenuService.fetchFromNetwork → MenuCache.save
///                                              ↘ returned to caller
///
/// An `actor` is used so concurrent calls from the app and widget (which run in
/// separate processes but share this type's source) can't race on the cache.
actor MenuService {
    static let shared = MenuService()

    private let session: URLSession
    private let cache = MenuCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches today's (or `date`'s) menu for a location from the network.
    /// On any failure, falls back to the cached menu for that same calendar day
    /// if one exists, so the UI can still show something useful offline.
    func menu(for location: DiningLocation, date: Date = Date()) async -> Result<DayMenu, MenuServiceError> {
        do {
            let fresh = try await fetchFromNetwork(location: location, date: date)
            cache.save(fresh, for: location)
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

    private func fetchFromNetwork(location: DiningLocation, date: Date) async throws -> DayMenu {
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

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "America/New_York")

        let targetDateString = dayFormatter.string(from: date)
        guard let matchingDay = week.days.first(where: { $0.date == targetDateString }) else {
            throw MenuServiceError.noDataForDate
        }

        // Group items under the most recent preceding section title, preserving
        // the order Flik returns them in. No category names or items are assumed
        // or hardcoded — whatever Flik provides is what gets displayed.
        var itemsByCategory: [String: [MenuItem]] = [:]
        var categoryOrder: [String] = []
        var currentCategory = "Menu"

        for entry in matchingDay.menuItems {
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

        let sortedCategories = sortCategories(categories, preferredOrder: location.preferredCategoryOrder)

        return DayMenu(
            locationSlug: location.schoolSlug,
            date: Calendar.current.startOfDay(for: date),
            categories: sortedCategories,
            fetchedAt: Date()
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

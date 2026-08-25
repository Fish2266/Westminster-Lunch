import WidgetKit

struct MaloneEntry: TimelineEntry {
    let date: Date
    let maloneMenu: DayMenu?
    /// Hawkins is fetched purely to source the three sandwich-station items
    /// for the widget's right column — this is still "the Malone widget,"
    /// just with a Hawkins-sourced second column.
    let hawkinsMenu: DayMenu?
    let errorMessage: String?
}

/// Timeline strategy: prefer cached data (written by the app, or by a previous
/// widget refresh) and only hit the network once per calendar day — the first
/// time the widget is asked for data after the date has rolled over. This
/// deliberately does NOT refresh throughout the day; lunch doesn't change once
/// published, so there's no reason to spend battery/network re-checking every
/// couple of hours. Applied independently to Malone and Hawkins, so a stale or
/// failed Hawkins fetch never blocks Malone's own data from showing.
///
/// WidgetKit itself imposes a system-wide daily refresh budget that Claude/the
/// developer cannot override — `.after(nextRefresh)` is a *request*, and the
/// system may refresh earlier (e.g. if the person opens the watch face) or later
/// (if the budget is exhausted). This is the most reliable, battery-efficient
/// strategy available; there is no WidgetKit API for guaranteed instant updates.
struct MaloneWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MaloneEntry {
        MaloneEntry(date: Date(), maloneMenu: nil, hawkinsMenu: nil, errorMessage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MaloneEntry) -> Void) {
        Task {
            let malone = await MenuService.shared.cachedMenu(for: .malone)
            let hawkins = await MenuService.shared.cachedMenu(for: .hawkins)
            completion(MaloneEntry(date: Date(), maloneMenu: malone, hawkinsMenu: hawkins, errorMessage: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MaloneEntry>) -> Void) {
        Task {
            let now = Date()

            async let maloneResult = fetchLocation(.malone, now: now)
            async let hawkinsResult = fetchLocation(.hawkins, now: now)

            let (maloneMenu, maloneError) = await maloneResult
            // A Hawkins failure is non-critical for this widget — it just means
            // the right column falls back to empty rather than the whole widget
            // showing an error state that's really about Malone.
            let (hawkinsMenu, _) = await hawkinsResult

            let entry = MaloneEntry(
                date: now,
                maloneMenu: maloneMenu,
                hawkinsMenu: hawkinsMenu,
                errorMessage: maloneMenu == nil ? maloneError : nil
            )

            let startOfToday = Calendar.current.startOfDay(for: now)
            let nextRefresh = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
                ?? now.addingTimeInterval(24 * 60 * 60)

            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    /// Returns cached data if it's from today already; otherwise fetches fresh
    /// (which also updates the cache for next time). On a failed fetch with no
    /// usable cache, returns the error message so the caller can decide whether
    /// it's worth surfacing.
    private func fetchLocation(_ location: DiningLocation, now: Date) async -> (DayMenu?, String?) {
        let cached = await MenuService.shared.cachedMenu(for: location)
        let cacheIsFreshEnough = cached.map { Calendar.current.isDate($0.date, inSameDayAs: now) } ?? false

        if cacheIsFreshEnough {
            return (cached, nil)
        }

        let result = await MenuService.shared.menu(for: location)
        switch result {
        case .success(let menu):
            return (menu, nil)
        case .failure(let error):
            return (cached, cached == nil ? error.localizedDescription : nil)
        }
    }
}

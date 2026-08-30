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
    /// How long the provider is willing to wait on the network before giving up
    /// and rendering from cache. WidgetKit budgets `getTimeline` only a few
    /// seconds of wall time on a real watch; if the completion handler hasn't
    /// been called by then the extension is terminated and watchOS shows an
    /// empty black card. Completing early with slightly stale data always beats
    /// not completing at all.
    private static let networkDeadline: TimeInterval = 6

    func placeholder(in context: Context) -> MaloneEntry {
        MaloneEntry(date: Date(), maloneMenu: nil, hawkinsMenu: nil, errorMessage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MaloneEntry) -> Void) {
        Task {
            completion(await cachedEntry(now: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MaloneEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await entryRacingDeadline(now: now)

            let startOfToday = Calendar.current.startOfDay(for: now)
            let nextRefresh = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
                ?? now.addingTimeInterval(24 * 60 * 60)

            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    /// Runs the real (possibly networking) entry build against a timer, and
    /// returns whichever finishes first — so this function always returns, and
    /// therefore the timeline completion handler is always called.
    private func entryRacingDeadline(now: Date) async -> MaloneEntry {
        await withTaskGroup(of: MaloneEntry?.self) { group in
            group.addTask { await networkEntry(now: now) }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.networkDeadline))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            return await cachedEntry(now: now)
        }
    }

    /// Cache-only entry: today's cached menu if there is one, otherwise the most
    /// recent menu cached for that location on any day. Never touches the network,
    /// so it's safe to use as the deadline fallback.
    private func cachedEntry(now: Date) async -> MaloneEntry {
        async let malone = bestCachedMenu(for: .malone, now: now)
        async let hawkins = bestCachedMenu(for: .hawkins, now: now)
        return MaloneEntry(
            date: now,
            maloneMenu: await malone,
            hawkinsMenu: await hawkins,
            errorMessage: nil
        )
    }

    private func bestCachedMenu(for location: DiningLocation, now: Date) async -> DayMenu? {
        // On a Saturday or Sunday the "current" day is Monday: no food is served
        // over the weekend, so the useful thing to show is the next school day's
        // lunch rather than an empty card.
        let displayDay = SchoolCalendar.currentDay(from: now)
        if let today = await MenuService.shared.cachedMenu(for: location, date: displayDay) {
            return today
        }
        return await MenuService.shared.mostRecentCachedMenu(for: location)
    }

    private func networkEntry(now: Date) async -> MaloneEntry {
        async let maloneResult = fetchLocation(.malone, now: now)
        async let hawkinsResult = fetchLocation(.hawkins, now: now)

        let (maloneMenu, maloneError) = await maloneResult
        // A Hawkins failure is non-critical for this widget — it just means
        // the right column falls back to empty rather than the whole widget
        // showing an error state that's really about Malone.
        let (hawkinsMenu, _) = await hawkinsResult

        return MaloneEntry(
            date: now,
            maloneMenu: maloneMenu,
            hawkinsMenu: hawkinsMenu,
            errorMessage: maloneMenu == nil ? maloneError : nil
        )
    }

    /// Tops up the cache with the current school day and the next one (a no-op
    /// when both were already downloaded today), then renders whichever of them
    /// is current. On a failed fetch it falls back to the newest menu cached for
    /// that location, and only reports an error when there's nothing to show.
    private func fetchLocation(_ location: DiningLocation, now: Date) async -> (DayMenu?, String?) {
        let result = await MenuService.shared.prefetchEssentials(for: location, now: now)
        switch result {
        case .success(let menu):
            return (menu, nil)
        case .failure(let error):
            let fallback = await MenuService.shared.mostRecentCachedMenu(for: location)
            return (fallback, fallback == nil ? error.localizedDescription : nil)
        }
    }
}

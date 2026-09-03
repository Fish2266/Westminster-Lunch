import Foundation
import Combine

@MainActor
final class MenuViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(DayMenu)
        case empty
        case error(String)
    }

    @Published var state: State = .loading
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    let location: DiningLocation
    private let service = MenuService.shared

    /// Which day the current `state` is for, and the calendar day it was
    /// fetched on. Both are needed to decide whether `state` still answers the
    /// question being asked — see `loadIfNeeded(for:now:)`.
    private var loaded: (day: Date, on: Date)?

    /// Deliberately does *not* take a date. The day belongs to the page, which
    /// passes it in per call: holding a copy here is what let a heading and the
    /// items under it come from two different days, and it is the same trap the
    /// widget's deep link once fell into with `location`.
    init(location: DiningLocation) {
        self.location = location
    }

    /// Called from the page's `.task` when it becomes the visible one. Loads
    /// only when what we have doesn't already answer for `date`, so swiping
    /// away and back doesn't refetch.
    ///
    /// The `loaded.on` check is the part that isn't obvious: a watch app stays
    /// resident for days, so without it a page loaded before midnight kept its
    /// download forever — including the page that had since *become* today,
    /// which would go on showing a menu Flik may not even have published yet
    /// when that copy was taken. This is the same rule
    /// `MenuService.cachedOrFreshMenu` applies to the cache; the two have to
    /// agree or this one silently overrides it.
    func loadIfNeeded(for date: Date, now: Date = Date()) async {
        let calendar = Calendar.current
        if let loaded,
           calendar.isDate(loaded.day, inSameDayAs: date),
           calendar.isDate(loaded.on, inSameDayAs: now) {
            return
        }
        await load(date: date, forcingNetwork: false)
    }

    /// The Refresh button and pull-to-refresh. Always goes to the network:
    /// asking for fresh data should get fresh data.
    func refresh(for date: Date) async {
        await load(date: date, forcingNetwork: true)
    }

    private func load(date: Date, forcingNetwork: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let result = forcingNetwork
            ? await service.menu(for: location, date: date)
            : await service.cachedOrFreshMenu(for: location, date: date)

        switch result {
        case .success(let menu):
            lastUpdated = menu.fetchedAt
            state = menu.isEmpty ? .empty : .loaded(menu)
            loaded = (day: date, on: Date())
        case .failure(let error):
            state = .error(error.localizedDescription)
            // Left unset so returning to a page that failed retries it. The
            // old `guard case .loading` meant one failure stuck until the
            // person found the Refresh button.
            loaded = nil
        }
    }
}

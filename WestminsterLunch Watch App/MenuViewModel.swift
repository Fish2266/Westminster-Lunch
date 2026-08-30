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
    let date: Date
    private let service = MenuService.shared

    init(location: DiningLocation, date: Date = Date()) {
        self.location = location
        self.date = date
    }

    /// Called from `.task {}` when the page appears. Only loads if we haven't
    /// already, so navigating back and forth doesn't refetch, and reuses a copy
    /// downloaded earlier today rather than re-requesting a menu that can't have
    /// changed — swiping across the week used to cost one download per page.
    func loadIfNeeded() async {
        guard case .loading = state else { return }
        await load(forcingNetwork: false)
    }

    /// The Refresh button and pull-to-refresh. Always goes to the network:
    /// asking for fresh data should get fresh data.
    func refresh() async {
        await load(forcingNetwork: true)
    }

    private func load(forcingNetwork: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let result = forcingNetwork
            ? await service.menu(for: location, date: date)
            : await service.cachedOrFreshMenu(for: location, date: date)

        switch result {
        case .success(let menu):
            lastUpdated = menu.fetchedAt
            state = menu.isEmpty ? .empty : .loaded(menu)
        case .failure(let error):
            state = .error(error.localizedDescription)
        }
    }
}

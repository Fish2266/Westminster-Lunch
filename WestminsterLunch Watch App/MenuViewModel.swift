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

    /// Called from `.task {}` — only loads if we haven't already, so navigating
    /// back and forth doesn't refetch unnecessarily. Automatic refresh on open.
    func loadIfNeeded() async {
        guard case .loading = state else { return }
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await service.menu(for: location, date: date)
        switch result {
        case .success(let menu):
            lastUpdated = menu.fetchedAt
            state = menu.isEmpty ? .empty : .loaded(menu)
        case .failure(let error):
            state = .error(error.localizedDescription)
        }
    }
}

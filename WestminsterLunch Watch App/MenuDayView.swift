import SwiftUI

/// The content for exactly one day's menu. `MenuView` hosts several of these
/// side by side in a paging `TabView` so the person can swipe left/right
/// between days; this view itself has no idea it's one page among many.
struct MenuDayView: View {
    /// The day this page is for, held here rather than read back out of the
    /// view model. The heading has to describe the page SwiftUI actually put on
    /// screen, and a `@StateObject` outlives the value that created it — so the
    /// two can only be guaranteed to agree if the date comes in as a view input.
    let date: Date

    /// Whether this is the page being looked at. `MenuView` builds every page in
    /// the window up front (a paging `TabView` is not lazy), so without this the
    /// eleven of them all reached for the network the moment a hall was opened.
    let isCurrentPage: Bool

    @StateObject private var viewModel: MenuViewModel

    init(location: DiningLocation, date: Date, isCurrentPage: Bool) {
        self.date = date
        self.isCurrentPage = isCurrentPage
        _viewModel = StateObject(wrappedValue: MenuViewModel(location: location))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                Group {
                    switch viewModel.state {
                    case .loading:
                        loadingState
                    case .loaded(let menu):
                        ForEach(menu.categories) { category in
                            MenuCategorySectionView(category: category)
                        }
                    case .empty:
                        emptyState
                    case .error(let message):
                        errorState(message: message)
                    }
                }

                footer
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        // Load when this page becomes the visible one, rather than when it is
        // merely built. Keyed on `isCurrentPage` so swiping onto a page that
        // was skipped over still triggers its load.
        .task(id: isCurrentPage) {
            guard isCurrentPage else { return }
            await viewModel.loadIfNeeded(for: date)
        }
        // Pull-to-refresh, supported on watchOS via ScrollView.
        .refreshable { await viewModel.refresh(for: date) }
    }

    /// Compared against the clock, not against the window `MenuView` built:
    /// the window is a snapshot taken when the screen first appeared, so on a
    /// resident app the two drift apart overnight and only the clock is right.
    /// `MenuView` re-centres the window when that happens.
    private var relativeDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY'S LUNCH"
        } else if calendar.isDateInYesterday(date) {
            return "YESTERDAY'S LUNCH"
        } else if calendar.isDateInTomorrow(date) {
            return "TOMORROW'S LUNCH"
        } else {
            return "LUNCH"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(relativeDayLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading lunch…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No menu available")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Flik hasn't published a menu for this day.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Couldn't load menu")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let lastUpdated = viewModel.lastUpdated {
                // Date as well as time when the copy isn't from today: "Updated
                // 3:24 PM" on its own reads as "just now" for a menu that was
                // actually downloaded before the app was last put away.
                Text("Updated \(lastUpdated.formatted(updatedStyle(for: lastUpdated)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.refresh(for: date) }
            } label: {
                Label(viewModel.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)
        }
        .padding(.top, 6)
    }

    private func updatedStyle(for updated: Date) -> Date.FormatStyle {
        Calendar.current.isDateInToday(updated)
            ? .dateTime.hour().minute()
            : .dateTime.month(.abbreviated).day().hour().minute()
    }
}

#Preview {
    NavigationStack {
        MenuDayView(location: .malone, date: Date(), isCurrentPage: true)
    }
}

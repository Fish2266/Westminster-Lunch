import SwiftUI

/// The content for exactly one day's menu. `MenuView` hosts several of these
/// side by side in a paging `TabView` so the person can swipe left/right
/// between days; this view itself has no idea it's one page among many.
struct MenuDayView: View {
    @StateObject private var viewModel: MenuViewModel

    init(location: DiningLocation, date: Date) {
        _viewModel = StateObject(wrappedValue: MenuViewModel(location: location, date: date))
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
        // Automatic refresh whenever this page first appears.
        .task { await viewModel.loadIfNeeded() }
        // Pull-to-refresh, supported on watchOS via ScrollView.
        .refreshable { await viewModel.refresh() }
    }

    private var relativeDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.date) {
            return "TODAY'S LUNCH"
        } else if calendar.isDateInYesterday(viewModel.date) {
            return "YESTERDAY'S LUNCH"
        } else if calendar.isDateInTomorrow(viewModel.date) {
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
            Text(viewModel.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
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
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label(viewModel.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)
        }
        .padding(.top, 6)
    }
}

#Preview {
    NavigationStack {
        MenuDayView(location: .malone, date: Date())
    }
}

import SwiftUI

/// Hosts a swipeable, day-by-day view of a location's menu. Swiping left goes
/// to earlier days, swiping right goes to later days, using watchOS's native
/// paging TabView (the same interaction watchOS users already know from
/// built-in apps like Activity).
///
/// Only a fixed window of days around today is offered — Flik/Nutrislice only
/// ever has real data for roughly the current week either direction, so
/// unlimited swiping would just page through empty "No menu available" screens
/// forever with no way to find your way back to today easily.
struct MenuView: View {
    let location: DiningLocation

    /// A week back, a week ahead. Adjust this range if Flik's site turns out
    /// to publish further out and further back swiping would be useful.
    private static let dayOffsetRange = -7...7

    @State private var selectedDayOffset = 0

    var body: some View {
        TabView(selection: $selectedDayOffset) {
            ForEach(Self.dayOffsetRange, id: \.self) { offset in
                MenuDayView(location: location, date: date(forOffset: offset))
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationTitle(location.displayName)
    }

    private func date(forOffset offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}

#Preview {
    NavigationStack {
        MenuView(location: .malone)
    }
}

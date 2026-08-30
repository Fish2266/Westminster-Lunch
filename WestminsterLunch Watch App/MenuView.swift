import SwiftUI

/// Hosts a swipeable, day-by-day view of a location's menu. Swiping left goes
/// to earlier days, swiping right goes to later days, using watchOS's native
/// paging TabView (the same interaction watchOS users already know from
/// built-in apps like Activity).
///
/// Only school days are pages: Saturdays and Sundays are skipped entirely,
/// because no food is served then and a weekend page could only ever show
/// "No menu available". Swiping right from Friday lands on Monday.
///
/// Only a fixed window of days around today is offered — Flik/Nutrislice only
/// ever has real data for roughly the current week either direction, so
/// unlimited swiping would just page through empty screens forever with no way
/// to find your way back to today easily.
struct MenuView: View {
    let location: DiningLocation

    /// A school week back, a school week ahead. Adjust if Flik turns out to
    /// publish further out and further swiping would be useful.
    private static let schoolDaysEitherWay = 5

    /// Resolved once, when the view is created, so the pages (and therefore
    /// the selected index) don't shift underneath the person if the date rolls
    /// over while they're looking at the screen.
    private let days: [Date]

    @State private var selectedIndex: Int

    init(location: DiningLocation) {
        self.location = location
        let days = SchoolCalendar.schoolDays(
            back: Self.schoolDaysEitherWay,
            forward: Self.schoolDaysEitherWay
        )
        self.days = days
        // Start on the centre page: today, or the next school day on a weekend.
        _selectedIndex = State(initialValue: Self.schoolDaysEitherWay)
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                MenuDayView(location: location, date: date)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationTitle(location.displayName)
    }
}

#Preview {
    NavigationStack {
        MenuView(location: .malone)
    }
}

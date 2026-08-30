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
    /// Fixed for the life of one instance. The pages below capture it when
    /// their view models are created, so presenting this view for a different
    /// hall requires a fresh identity — see the `.id(location)` on the
    /// `navigationDestination` in `WestminsterLunchApp`.
    let location: DiningLocation

    /// A school week back, a school week ahead. Adjust if Flik turns out to
    /// publish further out and further swiping would be useful.
    private static let schoolDaysEitherWay = 5

    /// Resolved once per visit to this screen, so the pages don't shift
    /// underneath the person if the date rolls over while they're looking at
    /// the screen.
    ///
    /// This has to be `@State`, not a plain `let` assigned in `init`: SwiftUI
    /// re-creates the view struct on every parent update, so a `let` would
    /// re-read `Date()` each time and quietly rebuild the window around a new
    /// "today". `State(initialValue:)` is honoured only when the view's
    /// identity is first established, which is the behaviour actually wanted.
    @State private var days: [Date]

    /// The selection is the day itself rather than an index into `days`, which
    /// is also what gives each page its `ForEach` identity. Keying by position
    /// instead would mean that if `days` ever did shift, page 3 would keep the
    /// `MenuDayView` (and its already-loaded `MenuViewModel`) built for the
    /// previous day 3 — showing one day's menu under another day's heading.
    @State private var selectedDay: Date

    init(location: DiningLocation) {
        self.location = location
        let days = SchoolCalendar.schoolDays(
            back: Self.schoolDaysEitherWay,
            forward: Self.schoolDaysEitherWay
        )
        _days = State(initialValue: days)
        // Start on the centre page: today, or the next school day on a weekend.
        // Taken from `days` rather than recomputed, so the two can't disagree.
        _selectedDay = State(initialValue: days[Self.schoolDaysEitherWay])
    }

    var body: some View {
        TabView(selection: $selectedDay) {
            ForEach(days, id: \.self) { day in
                MenuDayView(location: location, date: day)
                    .tag(day)
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

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
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    /// Fixed for the life of one instance. The pages below capture it when
    /// their view models are created, so presenting this view for a different
    /// hall requires a fresh identity — see the `.id(location)` on the
    /// `navigationDestination` in `WestminsterLunchApp`.
    let location: DiningLocation

    /// A school week back, a school week ahead. Adjust if Flik turns out to
    /// publish further out and further swiping would be useful.
    private static let schoolDaysEitherWay = 5

    /// The days offered as pages, and the one on screen.
    ///
    /// Both are `@State`, not values recomputed in `body`: SwiftUI re-creates
    /// the view struct on every parent update, so deriving them there would
    /// rebuild the window — and move the person's page — underneath them.
    ///
    /// The flip side is that they are a *snapshot*, and a watch app is not
    /// short-lived: it stays resident for days, so the window has to be
    /// re-centred explicitly whenever "now" has moved on. `showCurrentDay()`
    /// is the only thing that does that, and the two modifiers on `body` are
    /// the only things that call it.
    @State private var days: [Date]
    @State private var selectedDay: Date

    init(location: DiningLocation) {
        self.location = location
        let days = Self.window()
        _days = State(initialValue: days)
        // Start on the centre page: today, or the next school day on a weekend.
        // Taken from `days` rather than recomputed, so the two can't disagree.
        _selectedDay = State(initialValue: days[Self.schoolDaysEitherWay])
    }

    private static func window(from now: Date = Date()) -> [Date] {
        SchoolCalendar.schoolDays(
            back: schoolDaysEitherWay,
            forward: schoolDaysEitherWay,
            from: now
        )
    }

    /// The day the window is centred on — which is what "now" was when it was
    /// built, and so the thing to compare against the clock.
    private var anchorDay: Date {
        days[Self.schoolDaysEitherWay]
    }

    var body: some View {
        TabView(selection: $selectedDay) {
            // The selection is the day itself rather than an index into `days`,
            // which is also what gives each page its `ForEach` identity. Keying
            // by position instead would mean that when `days` shifts, page 3
            // keeps the `MenuDayView` built for the previous day 3 — showing one
            // day's menu under another day's heading.
            ForEach(days, id: \.self) { day in
                MenuDayView(
                    location: location,
                    date: day,
                    isCurrentPage: day == selectedDay
                )
                .tag(day)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationTitle(location.displayName)
        // Tapping the widget means "show me this hall's lunch, now". Replacing
        // the navigation path can't express that on its own: when the person is
        // already on this hall's screen the path is identical before and after,
        // so SwiftUI sees no change and the screen keeps whichever day was last
        // swiped to. The request carries a fresh token precisely so that the
        // no-visible-change case still arrives here.
        .onChange(of: router.openRequest) { _, request in
            guard let request, request.location == location else { return }
            showCurrentDay()
        }
        // Coming back to a screen that has been sitting here since before
        // midnight. Only re-centres when the date has actually rolled over, so
        // a deliberate swipe to next Tuesday survives a glance at the watch
        // face.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, anchorDay != SchoolCalendar.currentDay() else { return }
            showCurrentDay()
        }
    }

    /// Re-centres the window on the current school day and selects it.
    ///
    /// The window is rebuilt from the clock rather than searched for today
    /// inside `days`: by the time this is called the current day may have moved
    /// past the end of the old window entirely (leave the app open over a long
    /// weekend and it has), in which case there is no page to select.
    private func showCurrentDay() {
        let rebuilt = Self.window()
        if rebuilt != days {
            days = rebuilt
        }
        selectedDay = rebuilt[Self.schoolDaysEitherWay]
    }
}

#Preview {
    NavigationStack {
        MenuView(location: .malone)
    }
    .environmentObject(AppRouter())
}

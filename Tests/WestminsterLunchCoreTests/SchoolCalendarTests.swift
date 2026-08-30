import XCTest
@testable import WestminsterLunchCore

/// `SchoolCalendar` reads `Calendar.current`, so where a test would otherwise
/// hardcode "Saturday and Sunday" it asserts the underlying property instead
/// ("every day skipped is a non-school day"). That keeps the suite honest on a
/// machine whose locale defines the weekend differently, while still failing
/// loudly if the skipping logic itself breaks.
final class SchoolCalendarTests: XCTestCase {
    /// 2026-08-21 is a Friday, 08-22/23 the weekend, 08-24 the Monday after.
    private let friday = date(2026, 8, 21)
    private let saturday = date(2026, 8, 22)
    private let sunday = date(2026, 8, 23)
    private let monday = date(2026, 8, 24)

    private var weekendIsSaturdaySunday: Bool {
        Calendar.current.isDateInWeekend(saturday)
            && Calendar.current.isDateInWeekend(sunday)
            && !Calendar.current.isDateInWeekend(friday)
    }

    // MARK: - Stepping between school days

    func testNextSchoolDayLandsOnASchoolDayAndSkipsNothingInBetween() {
        for start in [friday, saturday, sunday, monday] {
            let next = SchoolCalendar.nextSchoolDay(after: start)

            XCTAssertGreaterThan(next, start, "the next school day must be strictly later")
            XCTAssertTrue(SchoolCalendar.isSchoolDay(next))

            // Nothing skipped over may have been a school day, or we jumped too far.
            var cursor = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            while cursor < next {
                XCTAssertFalse(
                    SchoolCalendar.isSchoolDay(cursor),
                    "\(cursor) was skipped but is a school day"
                )
                cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor)!
            }
        }
    }

    func testPreviousSchoolDayLandsOnASchoolDayAndSkipsNothingInBetween() {
        for start in [friday, saturday, sunday, monday] {
            let previous = SchoolCalendar.previousSchoolDay(before: start)

            XCTAssertLessThan(previous, start)
            XCTAssertTrue(SchoolCalendar.isSchoolDay(previous))

            var cursor = Calendar.current.date(byAdding: .day, value: -1, to: start)!
            while cursor > previous {
                XCTAssertFalse(SchoolCalendar.isSchoolDay(cursor))
                cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
            }
        }
    }

    func testFridayRollsForwardToMonday() throws {
        try XCTSkipUnless(weekendIsSaturdaySunday, "locale does not use a Sat/Sun weekend")
        XCTAssertEqual(SchoolCalendar.nextSchoolDay(after: friday), monday)
        XCTAssertEqual(SchoolCalendar.previousSchoolDay(before: monday), friday)
    }

    // MARK: - The "current" day

    func testCurrentDayOnAWeekendIsTheNextSchoolDay() throws {
        try XCTSkipUnless(weekendIsSaturdaySunday, "locale does not use a Sat/Sun weekend")
        XCTAssertEqual(SchoolCalendar.currentDay(from: saturday), monday)
        XCTAssertEqual(SchoolCalendar.currentDay(from: sunday), monday)
    }

    func testCurrentDayOnASchoolDayIsThatSameDay() {
        XCTAssertEqual(SchoolCalendar.currentDay(from: friday), friday)
    }

    func testCurrentDayIsAlwaysMidnightSoItMatchesACacheKey() {
        // A time-of-day component here would produce a menu whose `date` no
        // longer round-trips through MenuCache's day-granularity key.
        let midMorning = Calendar.current.date(byAdding: .hour, value: 10, to: friday)!
        XCTAssertEqual(SchoolCalendar.currentDay(from: midMorning), friday)
    }

    // MARK: - The cached window

    func testDaysToKeepCachedIsTwoAscendingSchoolDays() {
        let days = SchoolCalendar.daysToKeepCached(from: friday)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first, SchoolCalendar.currentDay(from: friday))
        XCTAssertLessThan(days[0], days[1])
        XCTAssertTrue(days.allSatisfy(SchoolCalendar.isSchoolDay))
    }

    func testSchoolDaysWindowIsCentredOnTodayAndContainsNoWeekends() {
        let days = SchoolCalendar.schoolDays(back: 5, forward: 5, from: saturday)

        XCTAssertEqual(days.count, 11, "5 back + today + 5 forward")
        XCTAssertEqual(days[5], SchoolCalendar.currentDay(from: saturday), "centre page is today")
        XCTAssertTrue(days.allSatisfy(SchoolCalendar.isSchoolDay), "a weekend became a page")
        XCTAssertEqual(days, days.sorted(), "pages must run oldest to newest")
        XCTAssertEqual(Set(days).count, days.count, "a day was duplicated")
    }

    func testSchoolDaysWindowWithNoBackOrForwardIsJustToday() {
        let days = SchoolCalendar.schoolDays(back: 0, forward: 0, from: friday)
        XCTAssertEqual(days, [friday])
    }
}

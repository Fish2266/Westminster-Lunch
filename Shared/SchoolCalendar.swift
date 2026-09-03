import Foundation

/// Weekday/weekend rules shared by the watch app and the widget.
///
/// Flik never publishes a menu on Saturday or Sunday — there is simply no food
/// served — so every part of the app treats weekends as days that don't exist:
/// swiping through days skips them, and "tomorrow" on a Friday means Monday.
enum SchoolCalendar {
    /// `Calendar.current` builds a fresh snapshot of the wearer's calendar on
    /// every access, so the loops below took one per step. They now take one
    /// per call — `schoolDays` runs on every `MenuView` initialization, which
    /// SwiftUI does on each parent update.
    private static var calendar: Calendar { Calendar.current }

    /// Monday–Friday. There's no holiday calendar here: a weekday with no
    /// published menu still shows up, and simply renders its empty state.
    static func isSchoolDay(_ date: Date) -> Bool {
        isSchoolDay(date, in: calendar)
    }

    private static func isSchoolDay(_ date: Date, in calendar: Calendar) -> Bool {
        !calendar.isDateInWeekend(date)
    }

    /// `date` itself if it's a school day, otherwise the next one after it.
    static func schoolDay(onOrAfter date: Date) -> Date {
        step(from: date, by: 1, startingAtDate: true)
    }

    static func nextSchoolDay(after date: Date) -> Date {
        step(from: date, by: 1, startingAtDate: false)
    }

    static func previousSchoolDay(before date: Date) -> Date {
        step(from: date, by: -1, startingAtDate: false)
    }

    /// Walks a day at a time in `direction` until it lands on a school day.
    ///
    /// Bounded rather than a bare `while`: every calendar this runs on has at
    /// most a two-day weekend, so more than a week of stepping means the date
    /// arithmetic has stopped advancing, and spinning forever on a watch is a
    /// far worse failure than returning the day we reached.
    private static func step(from date: Date, by direction: Int, startingAtDate: Bool) -> Date {
        let calendar = self.calendar
        var day = calendar.startOfDay(for: date)

        func advance() {
            day = calendar.date(byAdding: .day, value: direction, to: day)
                ?? day.addingTimeInterval(TimeInterval(direction) * 86_400)
        }

        if !startingAtDate {
            advance()
        }
        var stepsLeft = 7
        while !isSchoolDay(day, in: calendar), stepsLeft > 0 {
            advance()
            stepsLeft -= 1
        }
        return day
    }

    /// The day whose menu the app considers "current": today when school is in
    /// session, otherwise the next school day. On a Saturday this is Monday —
    /// showing Saturday's (nonexistent) menu would just be an empty screen.
    static func currentDay(from now: Date = Date()) -> Date {
        schoolDay(onOrAfter: now)
    }

    /// The two days that are always kept in the cache: the current school day
    /// and the one after it. These are what the widget and a freshly-opened app
    /// need to be able to render with no network at all.
    static func daysToKeepCached(from now: Date = Date()) -> [Date] {
        let today = currentDay(from: now)
        return [today, nextSchoolDay(after: today)]
    }

    /// A window of school days centred on the current one, weekends omitted —
    /// the pages `MenuView` lets the person swipe through.
    static func schoolDays(back: Int, forward: Int, from now: Date = Date()) -> [Date] {
        let today = currentDay(from: now)

        var past: [Date] = []
        var cursor = today
        for _ in 0..<back {
            cursor = previousSchoolDay(before: cursor)
            past.append(cursor)
        }

        var future: [Date] = []
        cursor = today
        for _ in 0..<forward {
            cursor = nextSchoolDay(after: cursor)
            future.append(cursor)
        }

        return past.reversed() + [today] + future
    }
}

import XCTest
@testable import WestminsterLunchCore

final class MenuCacheTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cache: MenuCache!

    override func setUp() {
        super.setUp()
        (defaults, suiteName) = makeThrowawayDefaults()
        cache = MenuCache(defaults: defaults)
    }

    override func tearDown() {
        destroyDefaults(suiteName: suiteName)
        cache = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func menu(
        for location: DiningLocation = .malone,
        on day: Date,
        items: [String] = ["Chicken Tenders"],
        // A whole second: the cache encodes dates as ISO8601, which has no
        // sub-second precision (see `testFetchedAtLosesSubSecondPrecision`), so
        // a `Date()` here would not survive a round trip byte-for-byte.
        fetchedAt: Date = Date(timeIntervalSince1970: 1_756_000_000)
    ) -> DayMenu {
        DayMenu(
            locationSlug: location.schoolSlug,
            date: day,
            categories: [MenuCategory(name: "Entrees", items: items.map { MenuItem(name: $0, description: nil) })],
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Round tripping

    func testSavedMenuLoadsBackForTheSameDay() {
        let day = date(2026, 8, 21)
        let saved = menu(on: day)

        cache.save(saved, for: .malone)

        XCTAssertEqual(cache.load(for: .malone, date: day), saved)
    }

    func testFetchedAtLosesSubSecondPrecision() throws {
        // Documented, not accidental: `fetchedAt` is only ever compared at
        // day granularity (`prefetchEssentials`) or shown as a wall-clock time
        // (`MenuViewModel.lastUpdated`), so seconds are precision enough. This
        // test exists so the truncation is a known property rather than a
        // surprise if something later starts comparing these exactly.
        let day = date(2026, 8, 21)
        let precise = Date(timeIntervalSince1970: 1_756_000_000.75)

        cache.save(menu(on: day, fetchedAt: precise), for: .malone)
        let loaded = try XCTUnwrap(cache.load(for: .malone, date: day))

        XCTAssertEqual(loaded.fetchedAt.timeIntervalSince1970, 1_756_000_000, accuracy: 0.001)
    }

    func testLoadingADifferentDayReturnsNothing() {
        cache.save(menu(on: date(2026, 8, 21)), for: .malone)

        XCTAssertNil(cache.load(for: .malone, date: date(2026, 8, 24)))
    }

    func testAnyTimeOfDayResolvesToTheSameEntry() {
        // The widget asks with `Date()`, the app with a start-of-day page date;
        // both have to hit the one entry.
        let day = date(2026, 8, 21)
        cache.save(menu(on: day), for: .malone)

        let lunchtime = Calendar.current.date(byAdding: .hour, value: 12, to: day)!
        XCTAssertNotNil(cache.load(for: .malone, date: lunchtime))
    }

    func testLocationsDoNotShareEntries() {
        let day = date(2026, 8, 21)
        cache.save(menu(for: .malone, on: day, items: ["Malone Item"]), for: .malone)
        cache.save(menu(for: .hawkins, on: day, items: ["Hawkins Item"]), for: .hawkins)

        XCTAssertEqual(cache.load(for: .malone, date: day)?.categories.first?.items.first?.name, "Malone Item")
        XCTAssertEqual(cache.load(for: .hawkins, date: day)?.categories.first?.items.first?.name, "Hawkins Item")
    }

    func testSavingTheSameDayTwiceOverwritesRatherThanDuplicates() {
        let day = date(2026, 8, 21)
        cache.save(menu(on: day, items: ["Old"]), for: .malone)
        cache.save(menu(on: day, items: ["New"]), for: .malone)

        XCTAssertEqual(cache.load(for: .malone, date: day)?.categories.first?.items.map(\.name), ["New"])
    }

    // MARK: - Most recent

    func testLoadMostRecentReturnsTheNewestDayNotTheNewestWrite() {
        // Written oldest-last on purpose: the answer must come from the menu's
        // own date, not from the order UserDefaults happens to hand keys back.
        cache.save(menu(on: date(2026, 8, 24), items: ["Monday"]), for: .malone)
        cache.save(menu(on: date(2026, 8, 21), items: ["Friday"]), for: .malone)

        XCTAssertEqual(
            cache.loadMostRecent(for: .malone)?.categories.first?.items.map(\.name),
            ["Monday"]
        )
    }

    func testLoadMostRecentIgnoresOtherLocations() {
        cache.save(menu(for: .hawkins, on: date(2026, 8, 24), items: ["Hawkins"]), for: .hawkins)
        cache.save(menu(for: .malone, on: date(2026, 8, 21), items: ["Malone"]), for: .malone)

        XCTAssertEqual(
            cache.loadMostRecent(for: .malone)?.categories.first?.items.map(\.name),
            ["Malone"]
        )
    }

    func testLoadMostRecentOnAnEmptyCacheIsNil() {
        XCTAssertNil(cache.loadMostRecent(for: .malone))
    }

    func testLoadMostRecentSkipsUndecodableEntriesRatherThanGivingUp() {
        // A cache entry written by an older build of the app could fail to
        // decode; that must not hide the good entry sitting behind it.
        cache.save(menu(on: date(2026, 8, 21), items: ["Good"]), for: .malone)
        defaults.set(Data("not json".utf8), forKey: "cached_menu_\(DiningLocation.malone.schoolSlug)_2026-8-24")

        XCTAssertEqual(
            cache.loadMostRecent(for: .malone)?.categories.first?.items.map(\.name),
            ["Good"]
        )
    }

    // MARK: - Pruning

    func testPruneDropsEntriesPastRetentionAndKeepsTheRest() {
        let today = Calendar.current.startOfDay(for: Date())
        let recent = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        let ancient = Calendar.current.date(byAdding: .day, value: -400, to: today)!

        cache.save(menu(on: recent), for: .malone)
        cache.save(menu(on: ancient), for: .malone)
        cache.save(menu(on: today), for: .malone)

        cache.pruneExpiredEntries(for: .malone)

        XCTAssertNotNil(cache.load(for: .malone, date: today))
        XCTAssertNotNil(cache.load(for: .malone, date: recent))
        XCTAssertNil(cache.load(for: .malone, date: ancient), "a 400-day-old entry should be gone")
    }

    func testPruneLeavesFutureDaysAlone() {
        // Tomorrow's menu is deliberately cached ahead of time; pruning must
        // never treat a future day as expired.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        cache.save(menu(on: Calendar.current.startOfDay(for: tomorrow)), for: .malone)

        cache.pruneExpiredEntries(for: .malone)

        XCTAssertNotNil(cache.load(for: .malone, date: tomorrow))
    }

    func testPruneDoesNotTouchOtherLocations() {
        let ancient = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        cache.save(menu(for: .hawkins, on: Calendar.current.startOfDay(for: ancient)), for: .hawkins)

        cache.pruneExpiredEntries(for: .malone)

        XCTAssertNotNil(cache.load(for: .hawkins, date: ancient))
    }

    func testPruneIgnoresUnrelatedKeysInTheSharedContainer() {
        // The App Group container is shared; nothing outside this cache's own
        // key prefix may be removed.
        defaults.set("keep me", forKey: "some_other_app_group_value")

        cache.save(menu(on: date(2026, 8, 21)), for: .malone)
        cache.pruneExpiredEntries(for: .malone)

        XCTAssertEqual(defaults.string(forKey: "some_other_app_group_value"), "keep me")
    }
}

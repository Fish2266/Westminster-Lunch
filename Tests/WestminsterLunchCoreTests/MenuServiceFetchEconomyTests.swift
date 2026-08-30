import XCTest
@testable import WestminsterLunchCore

/// How many times the app is willing to go to the network for a menu it already
/// has. Swiping through the week used to cost one full download per page.
final class MenuServiceFetchEconomyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var service: MenuService!

    private let thursday = date(2026, 8, 20)
    private let friday = date(2026, 8, 21)
    private let nextTuesday = date(2026, 8, 25)

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        (defaults, suiteName) = makeThrowawayDefaults()
        service = MenuService(session: StubURLProtocol.makeSession(), cache: MenuCache(defaults: defaults))
    }

    override func tearDown() {
        StubURLProtocol.reset()
        destroyDefaults(suiteName: suiteName)
        service = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A week response covering Thursday and Friday — whatever day is asked for.
    private func serveTheSameWeekForEveryRequest() {
        StubURLProtocol.handler = { _ in
            (200, weekJSON(days: [
                (date: "2026-08-20", menuItems: [sectionTitle("Entrees"), foodItem("Thursday Food")]),
                (date: "2026-08-21", menuItems: [sectionTitle("Entrees"), foodItem("Friday Food")]),
            ]))
        }
    }

    // MARK: - Concurrent pages share one download

    func testPagesOpeningTogetherShareASingleDownload() async {
        // The paging TabView brings several MenuDayViews to life at once, all
        // before any of them has written to the cache. One response covers the
        // whole week, so one request should be enough for all of them.
        serveTheSameWeekForEveryRequest()
        StubURLProtocol.responseDelay = 0.3

        async let first = service.menu(for: .malone, date: thursday)
        async let second = service.menu(for: .malone, date: friday)
        let (thursdayResult, fridayResult) = await (first, second)

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "the same week was downloaded twice")
        XCTAssertEqual(
            try? thursdayResult.get().categories.first?.items.first?.name,
            "Thursday Food"
        )
        XCTAssertEqual(
            try? fridayResult.get().categories.first?.items.first?.name,
            "Friday Food"
        )
    }

    func testACallerWhoseDayIsNotInTheRunningWeekStillGetsItsOwnDownload() async {
        // Correctness beats economy: piggybacking must never hand back a day
        // the response didn't actually contain.
        StubURLProtocol.handler = { request in
            // Matched against `absoluteString`, not `url.path`: `URL.path`
            // normalizes the trailing slash away, which silently made an
            // earlier version of this stub answer every request identically.
            let url = request.url?.absoluteString ?? ""
            if url.contains("/2026/08/25/") {
                return (200, weekJSON(days: [
                    (date: "2026-08-25", menuItems: [sectionTitle("Entrees"), foodItem("Tuesday Food")]),
                ]))
            }
            return (200, weekJSON(days: [
                (date: "2026-08-21", menuItems: [sectionTitle("Entrees"), foodItem("Friday Food")]),
            ]))
        }
        StubURLProtocol.responseDelay = 0.3

        async let first = service.menu(for: .malone, date: friday)
        async let second = service.menu(for: .malone, date: nextTuesday)
        let (fridayResult, tuesdayResult) = await (first, second)

        XCTAssertEqual(StubURLProtocol.requestCount, 2, "two different weeks need two requests")
        XCTAssertEqual(try? fridayResult.get().categories.first?.items.first?.name, "Friday Food")
        XCTAssertEqual(try? tuesdayResult.get().categories.first?.items.first?.name, "Tuesday Food")
    }

    func testConcurrentLocationsDoNotBlockEachOther() async {
        serveTheSameWeekForEveryRequest()
        StubURLProtocol.responseDelay = 0.2

        async let malone = service.menu(for: .malone, date: friday)
        async let hawkins = service.menu(for: .hawkins, date: friday)
        _ = await (malone, hawkins)

        XCTAssertEqual(StubURLProtocol.requestCount, 2, "each location needs its own request")
    }

    // MARK: - Reusing today's download

    func testAutomaticLoadReusesAMenuAlreadyDownloadedToday() async {
        serveTheSameWeekForEveryRequest()

        _ = await service.cachedOrFreshMenu(for: .malone, date: friday)
        let afterFirst = StubURLProtocol.requestCount

        // Swiping away and back, and onto a sibling day from the same response.
        _ = await service.cachedOrFreshMenu(for: .malone, date: friday)
        _ = await service.cachedOrFreshMenu(for: .malone, date: thursday)

        XCTAssertEqual(afterFirst, 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "revisiting a day should not re-download it")
    }

    func testExplicitRefreshAlwaysGoesToTheNetwork() async {
        serveTheSameWeekForEveryRequest()

        _ = await service.cachedOrFreshMenu(for: .malone, date: friday)
        _ = await service.menu(for: .malone, date: friday)

        XCTAssertEqual(
            StubURLProtocol.requestCount,
            2,
            "pull-to-refresh and the Refresh button must not be served from cache"
        )
    }

    func testAutomaticLoadStillFetchesWhenTheCachedCopyIsFromAnEarlierDay() async {
        // Yesterday's download of today's menu is not good enough — Flik may
        // not have published it yet when that copy was taken.
        let staleMenu = DayMenu(
            locationSlug: DiningLocation.malone.schoolSlug,
            date: friday,
            categories: [MenuCategory(name: "Entrees", items: [MenuItem(name: "Stale", description: nil)])],
            fetchedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        MenuCache(defaults: defaults).save(staleMenu, for: .malone)
        serveTheSameWeekForEveryRequest()

        let result = await service.cachedOrFreshMenu(for: .malone, date: friday)

        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        XCTAssertEqual(try? result.get().categories.first?.items.first?.name, "Friday Food")
    }

    func testAutomaticLoadFallsBackToTheStaleCopyWhenTheNetworkIsDown() async {
        let staleMenu = DayMenu(
            locationSlug: DiningLocation.malone.schoolSlug,
            date: friday,
            categories: [MenuCategory(name: "Entrees", items: [MenuItem(name: "Stale", description: nil)])],
            fetchedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        MenuCache(defaults: defaults).save(staleMenu, for: .malone)
        StubURLProtocol.handler = { _ in (500, Data()) }

        let result = await service.cachedOrFreshMenu(for: .malone, date: friday)

        XCTAssertEqual(try? result.get().categories.first?.items.first?.name, "Stale")
    }
}

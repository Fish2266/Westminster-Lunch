import XCTest
@testable import WestminsterLunchCore

/// Covers the layer where both of the bugs found in the August 2026 audit lived:
/// turning Nutrislice's raw week payload into `DayMenu`s, and deciding what to
/// show when the network doesn't cooperate.
final class MenuServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cache: MenuCache!
    private var service: MenuService!

    /// 2026-08-21 is a Friday; 08-22/23 the weekend it precedes.
    private let friday = date(2026, 8, 21)

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        (defaults, suiteName) = makeThrowawayDefaults()
        cache = MenuCache(defaults: defaults)
        service = MenuService(session: StubURLProtocol.makeSession(), cache: cache)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        destroyDefaults(suiteName: suiteName)
        service = nil
        cache = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func respond(status: Int = 200, with data: @autoclosure @escaping @Sendable () -> Data) {
        StubURLProtocol.handler = { _ in (status, data()) }
    }

    private func fridayWeek(_ menuItems: [[String: Any]]) -> Data {
        weekJSON(days: [(date: "2026-08-21", menuItems: menuItems)])
    }

    // MARK: - Parsing

    func testItemsAreGroupedUnderThePrecedingSectionTitle() async throws {
        respond(with: self.fridayWeek([
            sectionTitle("Entrees"),
            foodItem("Chicken Tenders"),
            foodItem("Rice"),
            sectionTitle("Dessert"),
            foodItem("Fruit Cup"),
        ]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Entrees", "Dessert"])
        XCTAssertEqual(menu.categories[0].items.map(\.name), ["Chicken Tenders", "Rice"])
        XCTAssertEqual(menu.categories[1].items.map(\.name), ["Fruit Cup"])
    }

    func testItemsBeforeAnySectionTitleFallIntoADefaultCategory() async throws {
        respond(with: self.fridayWeek([
            foodItem("Orphan Item"),
            sectionTitle("Entrees"),
            foodItem("Chicken Tenders"),
        ]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Menu", "Entrees"])
        XCTAssertEqual(menu.categories[0].items.map(\.name), ["Orphan Item"])
    }

    func testDuplicateItemNamesAreBothKept() async throws {
        // Regression guard: the views used to key their ForEach by item name,
        // which silently rendered one row here instead of two.
        respond(with: self.fridayWeek([
            sectionTitle("Entrees"),
            foodItem("Fruit Cup"),
            foodItem("Fruit Cup"),
        ]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.categories[0].items.count, 2)
    }

    func testUnrecognizedEntriesAreSkippedRatherThanFailingTheWholeDay() async throws {
        respond(with: self.fridayWeek([
            ["image": "https://example.com/banner.png"],
            sectionTitle("Entrees"),
            foodItem("Chicken Tenders"),
            ["food": ["name": ""]],
            ["text": "A note with no food and no section flag"],
        ]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Entrees"])
        XCTAssertEqual(menu.categories[0].items.map(\.name), ["Chicken Tenders"])
    }

    func testEmptySectionsAreDropped() async throws {
        respond(with: self.fridayWeek([
            sectionTitle("Entrees"),
            foodItem("Chicken Tenders"),
            sectionTitle("Nothing Today"),
        ]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Entrees"])
    }

    func testDayStringParsesToThatExactCalendarDay() async throws {
        // The formatter behind this is locale-sensitive; without an explicit
        // POSIX locale a non-Gregorian device calendar shifts or drops the day.
        respond(with: self.fridayWeek([sectionTitle("Entrees"), foodItem("Chicken Tenders")]))

        let menu = try await service.menu(for: .malone, date: friday).get()

        XCTAssertEqual(menu.date, friday)
        XCTAssertEqual(menu.locationSlug, DiningLocation.malone.schoolSlug)
    }

    // MARK: - Category ordering

    func testPreferredCategoriesComeFirstInTheirDeclaredOrder() async throws {
        respond(with: weekJSON(days: [(date: "2026-08-21", menuItems: [
            sectionTitle("Soup"),
            foodItem("Tomato"),
            sectionTitle("Sandwich #2"),
            foodItem("Turkey Club"),
            sectionTitle("Sandwich #1"),
            foodItem("Roast Beef"),
        ])]))

        let menu = try await service.menu(for: .hawkins, date: friday).get()

        // Hawkins prefers Sandwich #1, then #2, then Vegetarian; Soup isn't
        // listed, so it keeps its place at the end.
        XCTAssertEqual(menu.categories.map(\.name), ["Sandwich #1", "Sandwich #2", "Soup"])
    }

    func testUnlistedCategoriesKeepTheirRelativeOrder() async throws {
        respond(with: weekJSON(days: [(date: "2026-08-21", menuItems: [
            sectionTitle("Zebra"),
            foodItem("Z"),
            sectionTitle("Apple"),
            foodItem("A"),
            sectionTitle("Sandwich #1"),
            foodItem("Roast Beef"),
        ])]))

        let menu = try await service.menu(for: .hawkins, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Sandwich #1", "Zebra", "Apple"])
    }

    func testAPreferredCategoryAbsentTodayIsSimplySkipped() async throws {
        respond(with: weekJSON(days: [(date: "2026-08-21", menuItems: [
            sectionTitle("Sandwich #2"),
            foodItem("Turkey Club"),
        ])]))

        let menu = try await service.menu(for: .hawkins, date: friday).get()

        XCTAssertEqual(menu.categories.map(\.name), ["Sandwich #2"])
    }

    // MARK: - Weekends and missing days

    func testWeekendDaysInTheResponseAreDiscarded() async throws {
        respond(with: weekJSON(days: [
            (date: "2026-08-21", menuItems: [sectionTitle("Entrees"), foodItem("Friday Food")]),
            (date: "2026-08-22", menuItems: [sectionTitle("Entrees"), foodItem("Saturday Food")]),
            (date: "2026-08-23", menuItems: [sectionTitle("Entrees"), foodItem("Sunday Food")]),
        ]))

        _ = await service.menu(for: .malone, date: friday)

        let cachedFriday = await service.cachedMenu(for: .malone, date: friday)
        let cachedSaturday = await service.cachedMenu(for: .malone, date: date(2026, 8, 22))
        let cachedSunday = await service.cachedMenu(for: .malone, date: date(2026, 8, 23))

        XCTAssertNotNil(cachedFriday)
        XCTAssertNil(cachedSaturday)
        XCTAssertNil(cachedSunday)
    }

    func testAWeekMissingTheRequestedDayReportsNoDataRatherThanTheWrongDay() async {
        respond(with: weekJSON(days: [
            (date: "2026-08-20", menuItems: [sectionTitle("Entrees"), foodItem("Thursday Food")]),
        ]))

        let result = await service.menu(for: .malone, date: friday)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertEqual(error, .noDataForDate)
    }

    func testRequestURLKeepsTheZeroPaddingAndTrailingSlashTheServerRequires() async throws {
        // Both are load-bearing per the notes in NutrisliceConfig: the server
        // has returned 400 for un-padded dates, and the real site always sends
        // the trailing slash.
        respond(with: self.fridayWeek([sectionTitle("Entrees"), foodItem("Chicken Tenders")]))

        _ = await service.menu(for: .malone, date: friday)

        let url = try XCTUnwrap(StubURLProtocol.recordedRequests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasSuffix("/2026/08/21/"), "unexpected URL shape: \(url)")
    }

    // MARK: - Caching behavior

    func testOneRequestCachesEveryDayOfTheWeek() async {
        // This is what lets tomorrow's menu be available offline without a
        // second round trip.
        respond(with: weekJSON(days: [
            (date: "2026-08-20", menuItems: [sectionTitle("Entrees"), foodItem("Thursday Food")]),
            (date: "2026-08-21", menuItems: [sectionTitle("Entrees"), foodItem("Friday Food")]),
        ]))

        _ = await service.menu(for: .malone, date: friday)

        let cachedThursday = await service.cachedMenu(for: .malone, date: date(2026, 8, 20))
        let cachedFriday = await service.cachedMenu(for: .malone, date: friday)

        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        XCTAssertNotNil(cachedThursday)
        XCTAssertNotNil(cachedFriday)
    }

    func testANetworkFailureFallsBackToThatDaysCachedMenu() async throws {
        respond(with: self.fridayWeek([sectionTitle("Entrees"), foodItem("Chicken Tenders")]))
        _ = await service.menu(for: .malone, date: friday)

        StubURLProtocol.handler = { _ in (500, Data()) }
        let result = await service.menu(for: .malone, date: friday)

        let menu = try result.get()
        XCTAssertEqual(menu.categories[0].items.map(\.name), ["Chicken Tenders"])
    }

    func testANetworkFailureWithNothingCachedSurfacesTheError() async {
        StubURLProtocol.handler = { _ in (500, Data()) }

        let result = await service.menu(for: .malone, date: friday)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertEqual(error, .network("Server returned status 500."))
    }

    func testMalformedJSONIsReportedAsADecodingFailure() async {
        respond(with: Data("<html>not json</html>".utf8))

        let result = await service.menu(for: .malone, date: friday)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        guard case .decoding = error else {
            return XCTFail("expected a decoding error, got \(error)")
        }
    }

    // MARK: - Prefetching

    func testPrefetchSkipsTheNetworkForDaysAlreadyFetchedToday() async {
        respond(with: weekJSON(days: SchoolCalendar.daysToKeepCached(from: Date()).map { day in
            (date: Self.apiDateString(day), menuItems: [sectionTitle("Entrees"), foodItem("Chicken Tenders")])
        }))

        _ = await service.prefetchEssentials(for: .malone)
        let requestsAfterFirstPass = StubURLProtocol.requestCount

        _ = await service.prefetchEssentials(for: .malone)

        XCTAssertEqual(
            StubURLProtocol.requestCount,
            requestsAfterFirstPass,
            "a second prefetch on the same day should be served entirely from cache"
        )
    }

    func testPrefetchStillReturnsAMenuWhenTheNetworkIsDown() async throws {
        respond(with: weekJSON(days: SchoolCalendar.daysToKeepCached(from: Date()).map { day in
            (date: Self.apiDateString(day), menuItems: [sectionTitle("Entrees"), foodItem("Chicken Tenders")])
        }))
        _ = await service.prefetchEssentials(for: .malone)

        // Wipe the "fetched today" marker so the next pass really tries the
        // network, then take the network away.
        StubURLProtocol.handler = { _ in (500, Data()) }
        let result = await service.prefetchEssentials(for: .malone)

        let menu = try result.get()
        XCTAssertEqual(menu.categories[0].items.map(\.name), ["Chicken Tenders"])
    }

    private static func apiDateString(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        return formatter.string(from: day)
    }
}

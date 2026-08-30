import Foundation
@testable import WestminsterLunchCore

/// Builds a local-midnight `Date` from plain calendar numbers, so tests can talk
/// about "Friday the 21st" instead of juggling `TimeInterval`s.
func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    let components = DateComponents(year: year, month: month, day: day)
    guard let date = Calendar.current.date(from: components) else {
        fatalError("Could not build \(year)-\(month)-\(day) in the current calendar")
    }
    return Calendar.current.startOfDay(for: date)
}

/// A `UserDefaults` suite for one test, so the tests never read, write, or prune
/// the real App Group cache. Pair every call with `destroyDefaults`.
///
/// One fixed suite name is reused rather than a fresh UUID per test: XCTest runs
/// a class's tests serially and every `setUp` starts by emptying it, so there is
/// no cross-test bleed — and it means a full run leaves behind one preferences
/// file to clean up instead of dozens.
func makeThrowawayDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "test.WestminsterLunch.scratch"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create throwaway defaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

func destroyDefaults(suiteName: String) {
    let defaults = UserDefaults(suiteName: suiteName)
    defaults?.removePersistentDomain(forName: suiteName)
    UserDefaults.standard.removeSuite(named: suiteName)

    // `removePersistentDomain` empties the suite but leaves an empty plist
    // behind, so running the tests would otherwise litter the developer's
    // ~/Library/Preferences. Best effort — a failure here is not a test failure.
    let file = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Preferences")
        .appendingPathComponent("\(suiteName).plist")
    try? FileManager.default.removeItem(at: file)
}

/// Stubs out the network for `MenuService`. Tests set `handler` to decide what
/// each request returns; `MenuService` is then handed a session wired to this
/// protocol, so no real request is ever made.
final class StubURLProtocol: URLProtocol {
    /// Returns the status code and body for a request. Set before each test.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    /// Every request the service actually made, in order — lets tests assert
    /// that the cache spared a redundant fetch.
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []
    /// Holds each response open this long, so a test can have a second caller
    /// arrive while the first request is genuinely still in flight.
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0

    private static let lock = NSLock()

    static func reset() {
        handler = nil
        responseDelay = 0
        lock.withLock { recordedRequests = [] }
    }

    static var requestCount: Int {
        lock.withLock { recordedRequests.count }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `startLoading` runs on URLSession's own threads, so concurrent
        // requests would otherwise race on this array.
        Self.lock.withLock { Self.recordedRequests.append(request) }

        if Self.responseDelay > 0 {
            Thread.sleep(forTimeInterval: Self.responseDelay)
        }

        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Builds a Nutrislice-shaped week response. `days` maps a "yyyy-MM-dd" string
/// to the raw `menu_items` array for that day.
func weekJSON(days: [(date: String, menuItems: [[String: Any]])]) -> Data {
    let payload: [String: Any] = [
        "days": days.map { ["date": $0.date, "menu_items": $0.menuItems] }
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

func sectionTitle(_ text: String) -> [String: Any] {
    ["is_section_title": true, "text": text]
}

func foodItem(_ name: String, description: String? = nil) -> [String: Any] {
    var food: [String: Any] = ["name": name]
    if let description { food["description"] = description }
    return ["food": food]
}

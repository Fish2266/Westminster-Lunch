import XCTest
@testable import WestminsterLunchCore

/// The widget's deep link was dead for the whole life of the project: it wrote
/// `location=malone`, while the app resolved that value as a Nutrislice school
/// slug (`uppermiddle-school-malone-dining-hall`). Tapping the widget opened the
/// app but never navigated. These tests pin the round trip shut.
final class DeepLinkTests: XCTestCase {
    func testEveryLocationRoundTripsThroughItsOwnLink() throws {
        for location in DiningLocation.all {
            let url = try XCTUnwrap(DeepLink.url(for: location), "no URL for \(location.displayName)")
            XCTAssertEqual(
                DeepLink.location(from: url),
                location,
                "\(location.displayName)'s link does not resolve back to it"
            )
        }
    }

    func testMaloneLinkResolvesToMalone() throws {
        // The specific case the widget uses.
        let url = try XCTUnwrap(DeepLink.url(for: .malone))
        XCTAssertEqual(DeepLink.location(from: url), .malone)
    }

    func testLinkUsesTheSchoolSlugTheAppLooksUp() throws {
        // Guards the exact drift that broke it: the value in the URL has to be
        // whatever `DiningLocation.location(forSchoolSlug:)` matches on.
        let url = try XCTUnwrap(DeepLink.url(for: .malone))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let slug = components.queryItems?.first(where: { $0.name == "location" })?.value

        XCTAssertEqual(slug, DiningLocation.malone.schoolSlug)
        XCTAssertNotNil(DiningLocation.location(forSchoolSlug: try XCTUnwrap(slug)))
    }

    func testTheOldHardcodedLinkIsStillRejected() throws {
        // Documents the bug rather than the fix: this is what the widget used
        // to emit, and it must not silently start meaning something.
        let url = try XCTUnwrap(URL(string: "westminsterlunch://open?location=malone"))
        XCTAssertNil(DeepLink.location(from: url))
    }

    // MARK: - Links that aren't ours

    func testForeignSchemeIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://open?location=\(DiningLocation.malone.schoolSlug)"))
        XCTAssertNil(DeepLink.location(from: url))
    }

    func testWrongHostIsRejected() throws {
        let url = try XCTUnwrap(
            URL(string: "westminsterlunch://somethingelse?location=\(DiningLocation.malone.schoolSlug)")
        )
        XCTAssertNil(DeepLink.location(from: url))
    }

    func testMissingLocationIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "westminsterlunch://open"))
        XCTAssertNil(DeepLink.location(from: url))
    }

    func testUnknownLocationIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "westminsterlunch://open?location=not-a-dining-hall"))
        XCTAssertNil(DeepLink.location(from: url))
    }
}

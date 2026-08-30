import Foundation

/// The `westminsterlunch://` URL the widget uses to open a location's menu
/// directly, and the parser the app uses to read it back.
///
/// Both halves live here on purpose. They used to be written out separately —
/// the widget hardcoded `location=malone` while the app looked the value up as a
/// Nutrislice school slug (`uppermiddle-school-malone-dining-hall`) — so the
/// lookup always failed and tapping the widget only ever opened the home screen.
/// Building and parsing from the same `schoolSlug` makes that drift impossible.
enum DeepLink {
    static let scheme = "westminsterlunch"
    static let host = "open"
    static let locationQueryItem = "location"

    /// The URL that opens `location`'s menu.
    static func url(for location: DiningLocation) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: locationQueryItem, value: location.schoolSlug)]
        return components.url
    }

    /// The location `url` points at, or `nil` if it isn't one of our links or
    /// names a location this build doesn't know about.
    static func location(from url: URL) -> DiningLocation? {
        guard url.scheme == scheme,
              url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let slug = components.queryItems?
                  .first(where: { $0.name == locationQueryItem })?
                  .value
        else { return nil }

        return DiningLocation.location(forSchoolSlug: slug)
    }
}

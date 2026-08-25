import Foundation

/// Builds requests against Nutrislice's public, key-free "week menu" JSON API.
///
/// This is the same API used by long-standing community integrations (e.g. the
/// MMM-Nutrislice MagicMirror module, Home Assistant REST sensors) against
/// {district}.nutrislice.com and {district}.api.nutrislice.com deployments.
/// Flik's white-label domains follow the analogous {subdomain}.api.flikisdining.com
/// pattern.
///
/// `apiHost` below is confirmed directly from a Safari Network-tab capture of the
/// real westminster.flikisdining.com/menu page (both the Hawkins and Malone
/// requests hit this exact host, returning HTTP 200 JSON).
enum NutrisliceConfig {
    static let apiHost = "westminster.api.flikisdining.com"

    /// Builds the URL for the week (Mon–Sun) containing `date` for a given location.
    /// Nutrislice's endpoint returns a full week at a time; MenuService picks the
    /// single matching day out of the response.
    ///
    /// Month and day are zero-padded (e.g. "08", not "8") to match the exact URL
    /// shape confirmed via a live browser capture — the server returned a 400 for
    /// at least one un-padded variant, so don't remove the padding.
    static func weekMenuURL(for location: DiningLocation, weekOf date: Date) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost

        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        let monthString = String(format: "%02d", month)
        let dayString = String(format: "%02d", day)

        components.path = "/menu/api/weeks/school/\(location.schoolSlug)/menu-type/\(location.menuTypeSlug)/\(year)/\(monthString)/\(dayString)/"
        // Deliberately no ?format=json query param: the real site never sends one
        // (confirmed via capture) and gets JSON purely via the Accept header,
        // which MenuService already sets. Adding format=json here produced a
        // generic Django-level 400 rather than the expected menu JSON.

        return components.url
    }
}

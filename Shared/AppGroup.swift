import Foundation

/// Central place for the App Group identifier shared between the watch app
/// and the widget extension, so cached menu data can flow between them
/// without either one needing to hit the network.
///
/// This string has to match the App Groups capability enabled on *both* the
/// "WestminsterLunch Watch App" and "MaloneWidgetExtension" targets (see each
/// target's `.entitlements` file). If they ever drift apart the app and the
/// widget silently read two different, empty caches rather than failing loudly,
/// so change it in all three places at once.
enum AppGroup {
    static let identifier = "group.Christopherson.WestminsterLunch"
}

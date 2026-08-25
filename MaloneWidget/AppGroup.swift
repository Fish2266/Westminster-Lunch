import Foundation

/// Central place for the App Group identifier shared between the watch app
/// and the widget extension, so cached menu data can flow between them
/// without either one needing to hit the network.
///
/// SETUP REQUIRED IN XCODE:
/// 1. Select the "WestminsterLunch Watch App" target → Signing & Capabilities →
///    "+ Capability" → App Groups.
/// 2. Click "+" and add a group named exactly:
///       group.com.yourdomain.westminsterlunch
///    (replace "yourdomain" with your own reverse-DNS prefix — it just needs to
///    match your bundle identifier's prefix, e.g. group.com.janedoe.westminsterlunch)
/// 3. Repeat steps 1–2 for the "MaloneWidgetExtension" target, using the exact
///    same group identifier.
/// 4. Update the string below to match exactly what you created in Xcode.
enum AppGroup {
    static let identifier = "group.Christopherson.WestminsterLunch"
}

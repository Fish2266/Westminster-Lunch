import SwiftUI
import Combine

@main
struct WestminsterLunchApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $router.path) {
                ContentView()
                    .navigationDestination(for: DiningLocation.self) { location in
                        // A different dining hall is a different screen, and
                        // has to be declared as one. Tapping the widget while
                        // already viewing Hawkins replaces the stack's single
                        // entry rather than growing it, so without this SwiftUI
                        // reuses the existing view's identity: the title tracks
                        // `location` and updates to "Malone", but MenuDayView's
                        // @StateObject was built once with Hawkins and keeps
                        // serving the Hawkins menu underneath it.
                        MenuView(location: location)
                            .id(location)
                    }
            }
            .environmentObject(router)
            .onOpenURL { url in
                router.handle(url: url)
            }
            // Warm the shared cache with the current school day and the next
            // one every time the app opens, so both the app and the widget can
            // render them later with no network at all. Fetching a day pulls
            // its whole week down in one request, so this is normally a single
            // call per location.
            .task {
                await withTaskGroup(of: Void.self) { group in
                    for location in DiningLocation.all {
                        group.addTask {
                            await MenuService.shared.prefetchEssentials(for: location)
                        }
                    }
                }
            }
        }
    }
}

/// Handles the deep link fired when the person taps the Malone widget. The URL
/// is built and parsed by `DeepLink`, so the widget's link and this lookup are
/// guaranteed to agree.
@MainActor
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    /// The most recent request to open a hall's menu, published separately from
    /// `path` because the path alone cannot express every one of them.
    ///
    /// The link's promise is "this hall's lunch, today". Replacing `path` gets
    /// the person to the right hall, but when they are already on that hall's
    /// screen the new path is *equal* to the old one, so nothing about the view
    /// hierarchy changes and the screen goes on showing whichever day they had
    /// swiped to — the widget appearing to do nothing but wake the app.
    /// `MenuView` watches this instead, and the token is what makes two taps
    /// distinguishable when the location is the same both times.
    @Published private(set) var openRequest: OpenRequest?

    struct OpenRequest: Equatable {
        let location: DiningLocation
        /// Only its inequality matters; nothing reads the value.
        let token: UUID
    }

    /// The day is deliberately not carried in the URL. A widget URL is baked
    /// into a timeline entry that WidgetKit may still be showing well after the
    /// date it was built for — a literal date in the link would then open the
    /// app on a day that has already passed. "Now" is resolved here, when the
    /// tap actually happens.
    func handle(url: URL) {
        guard let location = DeepLink.location(from: url) else { return }

        openRequest = OpenRequest(location: location, token: UUID())
        path = NavigationPath()
        path.append(location)
    }
}

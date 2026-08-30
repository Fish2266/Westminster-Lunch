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

    func handle(url: URL) {
        guard let location = DeepLink.location(from: url) else { return }

        path = NavigationPath()
        path.append(location)
    }
}

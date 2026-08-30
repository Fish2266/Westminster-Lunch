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
                        MenuView(location: location)
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

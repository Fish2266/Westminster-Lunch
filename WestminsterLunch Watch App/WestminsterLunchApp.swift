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

/// Handles the deep link fired when the person taps the Malone widget:
/// westminsterlunch://open?location=malone
@MainActor
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    func handle(url: URL) {
        guard url.scheme == "westminsterlunch" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let slug = components.queryItems?.first(where: { $0.name == "location" })?.value
        guard let slug, let location = DiningLocation.location(forSchoolSlug: slug) else { return }

        path = NavigationPath()
        path.append(location)
    }
}

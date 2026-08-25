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

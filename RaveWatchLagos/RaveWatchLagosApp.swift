import SwiftUI

@main
struct RaveWatchLagosApp: App {
    @StateObject private var eventStore = EventStore()
    @StateObject private var userStore = UserStore()
    @StateObject private var metrics = MetricsService()
    @StateObject private var newEventsStore = NewEventsStore()
    @StateObject private var tourStore = TourStore()
    @StateObject private var soundService = SoundService()
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var tourController = TourController()
    @StateObject private var coordinator = TabNavigation()

    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(eventStore)
            .environmentObject(userStore)
            .environmentObject(metrics)
            .environmentObject(newEventsStore)
            .environmentObject(tourStore)
            .environmentObject(soundService)
            .environmentObject(toastCenter)
            .environmentObject(tourController)
            .environmentObject(coordinator)
            .preferredColorScheme(userStore.theme.colorScheme)
            .task {
                // The stores and feed load behind the splash; the tour
                // follows the splash on first launch.
                eventStore.newEventsStore = newEventsStore
                await eventStore.load()
            }
            .onAppear {
                // Swipe sounds start loading NOW, behind the 2-second
                // splash, so they are fully loaded before the first
                // swipe can happen.
                soundService.preload()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                    }
                    if !tourStore.seen {
                        tourController.start()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Returning to the app refetches the feed when more
                // than 15 minutes passed since the last fetch kick.
                if phase == .active {
                    Task {
                        await eventStore.resumeRefetchIfNeeded()
                    }
                }
            }
        }
    }
}

// MARK: - Shared styling

extension Color {
    /// Deep purple accent (Material 3 seed colour), matching the
    /// Android app's `ColorScheme.fromSeed(deepPurple)` and the
    /// AccentColor asset.
    static let raveAccent = Color("AccentColor")
}

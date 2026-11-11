import SwiftUI

@main
struct RaveWatchLagosApp: App {
    @StateObject private var eventStore = EventStore()
    @StateObject private var userStore = UserStore()

    /// v1 ships with the local-only attending service. Swap in
    /// `SupabaseAttendingService` here once Supabase credentials exist —
    /// see the TODO in Services/AttendingService.swift.
    private let attendingService: AttendingService = LocalAttendingService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventStore)
                .environmentObject(userStore)
                .environment(\.attendingService, attendingService)
                .preferredColorScheme(userStore.theme.colorScheme)
                .task {
                    await eventStore.load()
                }
        }
    }
}

// MARK: - Attending service environment key

private struct AttendingServiceKey: EnvironmentKey {
    static let defaultValue: AttendingService = LocalAttendingService()
}

extension EnvironmentValues {
    var attendingService: AttendingService {
        get { self[AttendingServiceKey.self] }
        set { self[AttendingServiceKey.self] = newValue }
    }
}

// MARK: - Shared styling

extension Color {
    /// Neon pink accent, matching the app icon and the AccentColor asset.
    static let raveAccent = Color("AccentColor")

    /// Near-black night background. The system background is used in light
    /// mode; this is applied explicitly where the night look is wanted.
    static let nightBackground = Color(red: 0.04, green: 0.04, blue: 0.06)
}

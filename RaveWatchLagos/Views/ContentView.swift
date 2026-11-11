import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userStore: UserStore

    var body: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }

            FollowingView()
                .tabItem {
                    Label("Following", systemImage: "heart")
                }
                .badge(userStore.followedCount)

            ProfileView()
                .tabItem {
                    Label("You", systemImage: "person")
                }
        }
        .tint(.raveAccent)
    }
}

#Preview {
    ContentView()
        .environmentObject(EventStore())
        .environmentObject(UserStore())
}

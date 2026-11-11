import SwiftUI

/// Events the user has followed, in date order.
struct FollowingView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore

    private var followedEvents: [Event] {
        eventStore.events
            .filter { userStore.followedEventIDs.contains($0.id) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if followedEvents.isEmpty {
                    ContentUnavailableView(
                        "Nothing followed yet",
                        systemImage: "heart",
                        description: Text("Tap the heart on any event to keep it here.")
                    )
                } else {
                    List {
                        ForEach(followedEvents) { event in
                            NavigationLink(value: event) {
                                EventRow(event: event)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Following")
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
        }
    }
}

#Preview {
    FollowingView()
        .environmentObject(EventStore())
        .environmentObject(UserStore())
}

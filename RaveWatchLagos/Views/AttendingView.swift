import SwiftUI
import UIKit

/// Attending tab, ported from `lib/screens/attending_screen.dart`.
///
/// The events this user marked "Attending" on their detail pages, in
/// date order. Card swipes: right = Share, left = Delete (not
/// attending), with Undo.
struct AttendingView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var metrics: MetricsService
    @EnvironmentObject private var newEventsStore: NewEventsStore
    @EnvironmentObject private var soundService: SoundService
    @EnvironmentObject private var tourController: TourController
    @EnvironmentObject private var coordinator: TabNavigation
    @EnvironmentObject private var toastCenter: ToastCenter

    /// Fired when the user performs a card swipe on this tab / taps
    /// Share my picks, so the tour can advance itself.
    var onTourCardAction: () -> Void = {}
    var onTourShareAction: () -> Void = {}

    @State private var demoGone: Set<String> = []

    private var mine: [Event] {
        eventStore.upcomingEvents
            .filter { userStore.isAttending($0) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// Tour demo mode: while the tour runs, an empty list shows example
    /// cards so the tour has something to point at; they vanish with
    /// the tour and never touch the user's real list.
    private var tourDemo: Bool { tourController.active && mine.isEmpty }
    private var shown: [Event] { tourDemo ? TourDemoEvents.demoEvents() : mine }

    var body: some View {
        NavigationStack(path: $coordinator.attendingPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if mine.isEmpty && !tourDemo {
                        Text("Nothing here yet — open an event and tap \"Yes\" under \"Will you be attending?\" on its page.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                    } else {
                        if tourDemo {
                            Text("Example cards — shown just for the tour. Say Yes to a night and it collects here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                        }
                        if tourDemo {
                            ForEach(demoVisible, id: \.id) { event in
                                ListCardSwipe(
                                    onShare: { onTourCardAction() },
                                    onDelete: {
                                        demoGone.insert(event.id)
                                        onTourCardAction()
                                    }
                                ) {
                                    demoCard(event)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .if(event.id == demoVisible.first?.id) { view in
                                    view.tourAnchor(.attendingCard)
                                }
                            }
                        } else {
                            ForEach(shown) { event in
                                ListCardSwipe(
                                    onShare: {
                                        soundService.playTick()
                                        shareEvent(event)
                                        onTourCardAction()
                                    },
                                    onDelete: { deleteEvent(event) }
                                ) {
                                    EventCardView(
                                        event: event,
                                        attendingCount: eventStore.attendingCount(for: event),
                                        followingCount: eventStore.followingCount(for: event),
                                        isNew: newEventsStore.isNew(event.id),
                                        onShare: { shareEvent(event) },
                                        onTap: { openEvent(event) }
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .if(event.id == shown.first?.id) { view in
                                        view.tourAnchor(.attendingCard)
                                    }
                                }
                            }
                        }
                    }
                }
                .tourAnchor(.attendingBody)
            }
            .navigationTitle("Attending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !mine.isEmpty || tourDemo {
                        Button {
                            if mine.isEmpty {
                                // Tour demo: no sheet for example picks —
                                // the tap itself is the lesson.
                                onTourShareAction()
                                return
                            }
                            sharePicks()
                            onTourShareAction()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tourAnchor(.attendingShare)
                        .accessibilityLabel("Share my picks")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { userStore.toggleTheme() } label: {
                        Image(systemName: userStore.theme == .night ? "sun.max" : "moon")
                    }
                    .accessibilityLabel("Toggle theme")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coordinator.attendingPath.append(Route.settings) } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                routeDestination(route)
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .event(let event):
            EventDetailView(event: event)
        case .eventReadOnly(let event):
            EventDetailView(event: event, readOnly: true)
        case .settings:
            SettingsView()
        case .privacy:
            PrivacyPolicyView()
        }
    }

    // MARK: - Demo cards

    private var demoVisible: [Event] {
        TourDemoEvents.demoEvents().filter { !demoGone.contains($0.id) }
    }

    private func demoCard(_ event: Event) -> some View {
        EventCardView(
            event: event,
            attendingCount: event.attendingCount,
            followingCount: event.followingCount,
            isNew: false,
            onShare: { onTourCardAction() },
            onTap: { coordinator.attendingPath.append(Route.eventReadOnly(event)) }
        )
    }

    // MARK: - Actions

    private func openEvent(_ event: Event) {
        newEventsStore.markRead(event.id)
        coordinator.attendingPath.append(Route.event(event))
    }

    private func shareEvent(_ event: Event) {
        metrics.recordShare(event.id)
        ShareService.presentShareSheet(ShareService.shareText(for: event))
    }

    private func sharePicks() {
        guard let text = ShareService.sharePicksText(mine, attending: true) else { return }
        for event in mine {
            metrics.recordShare(event.id)
        }
        ShareService.presentShareSheet(text)
    }

    private func deleteEvent(_ event: Event) {
        soundService.playClick()
        if userStore.setAttending(event, going: false) {
            Task {
                await eventStore.bumpAttending(event: event, delta: -1)
            }
        }
        onTourCardAction()
        // Undo snackbar (3s): restores the attendance and bumps +1 back.
        toastCenter.show("Removed from Attending", duration: 3, actionLabel: "Undo") {
            if userStore.setAttending(event, going: true) {
                Task {
                    await eventStore.bumpAttending(event: event, delta: 1)
                }
            }
        }
    }
}

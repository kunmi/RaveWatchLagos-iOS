import SwiftUI
import UIKit

/// Following & Alerts, ported from `lib/screens/following_screen.dart`.
///
/// Events are followed from their detail pages ("Follow for alerts");
/// this screen lists the followed events and shows an alert inbox
/// derived from their change logs. Area/genre follows were removed in
/// v0.8.7 — follow events and see the alerts, nothing else. Push (FCM)
/// lands in Phase 1 backend.
///
/// Alert inbox: change-log entries from followed events, GROUPED BY
/// EVENT — the event with the newest change first, each event's changes
/// newest first, never more than the 3 LATEST alerts per event. The
/// inbox starts COLLAPSED, and each group starts collapsed too. Every
/// alert shows the date its change was discovered.
///
/// Card swipes: right = Share, left = Delete (unfollow), with Undo.
struct FollowingView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var metrics: MetricsService
    @EnvironmentObject private var newEventsStore: NewEventsStore
    @EnvironmentObject private var soundService: SoundService
    @EnvironmentObject private var tourController: TourController
    @EnvironmentObject private var coordinator: TabNavigation
    @EnvironmentObject private var toastCenter: ToastCenter

    /// Fired when the user performs a card swipe on this tab, so the
    /// tour can advance itself.
    var onTourCardAction: () -> Void = {}

    @State private var inboxExpanded = false
    @State private var openGroups: Set<String> = []
    @State private var demoGone: Set<String> = []

    private var followed: [Event] {
        eventStore.upcomingEvents.filter { userStore.isFollowing($0) }
    }

    /// Tour demo mode: while the tour runs, an empty list shows example
    /// cards so the tour has something to point at; they vanish with
    /// the tour and never touch the user's real list.
    private var tourDemo: Bool { tourController.active && followed.isEmpty }
    private var shown: [Event] { tourDemo ? TourDemoEvents.demoEvents() : followed }

    private struct AlertEntry: Hashable {
        let description: String
        let date: Date
    }
    private struct AlertGroup: Hashable {
        let eventID: String
        let eventName: String
        let entries: [AlertEntry]
    }

    private var alertGroups: [AlertGroup] {
        var groups: [AlertGroup] = []
        for event in shown {
            guard !event.changeLog.isEmpty else { continue }
            var entries = event.changeLog.compactMap { entry -> AlertEntry? in
                guard let date = entry.parsedDate else { return nil }
                return AlertEntry(description: entry.description, date: date)
            }
            entries.sort { $0.date > $1.date }
            if entries.count > 3 { entries = Array(entries.prefix(3)) }
            groups.append(AlertGroup(eventID: event.id, eventName: event.name, entries: entries))
        }
        groups.sort { ($0.entries.first?.date ?? .distantPast) > ($1.entries.first?.date ?? .distantPast) }
        return groups
    }

    private var totalAlerts: Int {
        alertGroups.reduce(0) { $0 + $1.entries.count }
    }

    var body: some View {
        NavigationStack(path: $coordinator.followingPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Followed events")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .id("top")

                        if tourDemo {
                            Text("Example cards — shown just for the tour. Follow a night and it collects here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        }

                        if shown.isEmpty {
                            Text("None yet — open an event and tap \"Follow for alerts\".")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        } else if tourDemo {
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
                                    view.tourAnchor(.followingCard)
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
                                        view.tourAnchor(.followingCard)
                                    }
                                }
                            }
                        }

                        alertInbox
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                            .id("inbox")
                    }
                    .tourAnchor(.followingBody)
                }
                .onChange(of: tourController.followingScrollTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(tourController.followingScrollToBottom ? "inbox" : "top",
                                       anchor: .top)
                    }
                }
            }
            .navigationTitle("Following & Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !followed.isEmpty || tourDemo {
                        Button {
                            sharePicks()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
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
                    Button { coordinator.followingPath.append(Route.settings) } label: {
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
            onTap: { coordinator.followingPath.append(Route.eventReadOnly(event)) }
        )
    }

    // MARK: - Alert inbox

    private var alertInbox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                inboxExpanded.toggle()
            } label: {
                HStack {
                    Text(totalAlerts == 0 ? "Alert inbox" : "Alert inbox (\(totalAlerts))")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: inboxExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .tourAnchor(.followingInbox)
            .padding(.vertical, 4)

            if inboxExpanded {
                if alertGroups.isEmpty {
                    Text("No alerts yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(alertGroups, id: \.eventID) { group in
                        Button {
                            if openGroups.contains(group.eventID) {
                                openGroups.remove(group.eventID)
                            } else {
                                openGroups.insert(group.eventID)
                            }
                        } label: {
                            HStack {
                                Text("\(group.eventName) (\(group.entries.count))")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: openGroups.contains(group.eventID) ? "chevron.up" : "chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)

                        if openGroups.contains(group.eventID) {
                            ForEach(group.entries, id: \.description) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "bell")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.description)
                                            .font(.subheadline)
                                        Text("Discovered \(discoveredLabel(entry.date))")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func discoveredLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM yyyy"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = Event.lagosTimeZone
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func openEvent(_ event: Event) {
        newEventsStore.markRead(event.id)
        coordinator.followingPath.append(Route.event(event))
    }

    private func shareEvent(_ event: Event) {
        metrics.recordShare(event.id)
        ShareService.presentShareSheet(ShareService.shareText(for: event))
    }

    private func sharePicks() {
        guard let text = ShareService.sharePicksText(followed, attending: false) else { return }
        for event in followed {
            metrics.recordShare(event.id)
        }
        ShareService.presentShareSheet(text)
    }

    private func deleteEvent(_ event: Event) {
        guard userStore.isFollowing(event) else { return }
        soundService.playClick()
        userStore.toggleFollow(event)
        Task {
            await eventStore.bumpFollowing(event: event, delta: -1)
        }
        onTourCardAction()
        // Undo snackbar (3s): restores the follow and bumps +1 back.
        toastCenter.show("Removed from Following", duration: 3, actionLabel: "Undo") {
            if !userStore.isFollowing(event) {
                userStore.toggleFollow(event)
                Task {
                    await eventStore.bumpFollowing(event: event, delta: 1)
                }
            }
        }
    }
}

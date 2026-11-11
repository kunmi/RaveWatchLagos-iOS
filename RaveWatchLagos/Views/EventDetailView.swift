import SwiftUI
import UIKit

/// Full event page, ported from `lib/screens/event_detail_screen.dart`.
///
/// Order, as in Flutter: flyer (flippable, tap for full-screen) →
/// name → date + doors → venue + area → address → Directions/Bolt/
/// inDrive row → Venues by day → description → "Tickets — <status>" →
/// price tiers → ticket note → Get tickets (via the leave-app
/// interstitial) → Share event → Follow → following count line →
/// "Will you be attending?" Yes/No → attending count line → age limit
/// → unproven-promoter warning → last verified → sources → change
/// history (collapsed, newest first, last block on the page).
///
/// The detail page fetches live counts on init (per-event fetch,
/// fresher wins, feed fallback) and records an open metric on init.
/// The share button sits in the app bar, as in Flutter.
struct EventDetailView: View {
    let event: Event
    /// When true, the page is a read-only tour look — no stores, so the
    /// example event can be looked at but not followed or counted.
    var readOnly = false

    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var metrics: MetricsService
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.openURL) private var openURL

    @State private var showViewer = false
    @State private var leaveApp: LeaveAppRequest?
    @State private var historyOpen = false

    private struct LeaveAppRequest: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let kind: LeaveAppView.Kind
    }

    private var attendingCount: Int? { eventStore.attendingCount(for: event) }
    private var followingCount: Int? { eventStore.followingCount(for: event) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if event.detailImageURL != nil {
                    FlippableFlyerView(event: event) {
                        showViewer = true
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(dateLine)
                    Text("\(event.venueName ?? "Venue TBA") · \(event.area ?? "")")
                    if let address = event.address, !address.isEmpty {
                        Text(address)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if event.directionsURL != nil {
                    rideRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !event.dayVenues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Venues by day")
                                .font(.headline)
                            ForEach(event.dayVenues, id: \.date) { dayVenue in
                                Text("• \(dayVenueLabel(dayVenue)) — \(dayVenue.venue)")
                            }
                        }
                        .padding(.top, 10)
                    }

                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .padding(.top, 10)
                    }

                    ticketsSection

                    if !readOnly {
                        shareButton
                        followButton
                        if let followingCount {
                            Text(followingCountLine(followingCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }

                        attendingSection
                    }

                    if let age = event.ageLimit, !age.isEmpty {
                        Text("Age limit: \(age)")
                            .padding(.top, 12)
                    }

                    if event.showNewPromoterTag {
                        Text("⚠ New / unproven promoter — listed from organiser posts, not yet corroborated.")
                            .padding(.top, 8)
                    }

                    if let verified = event.lastVerifiedDisplay {
                        Text("Last verified: \(verified)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }

                    sourcesSection

                    if !sortedHistory.isEmpty {
                        changeHistorySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareEvent()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share event")
            }
        }
        .fullScreenCover(isPresented: $showViewer) {
            if let url = event.detailImageURL {
                FlyerViewerView(url: url) { showViewer = false }
            }
        }
        .navigationDestination(item: $leaveApp) { request in
            LeaveAppView(
                eventName: event.name,
                url: request.url,
                kind: request.kind,
                onContinue: {
                    leaveApp = nil
                    if request.kind == .tickets {
                        metrics.recordTicketTap(event.id)
                    } else {
                        metrics.recordSourceTap(event.id)
                    }
                    openURL(request.url)
                },
                onStay: { leaveApp = nil }
            )
        }
        .task {
            guard !readOnly else { return }
            metrics.recordOpen(event.id)
            await eventStore.fetchCounts(for: event)
        }
    }

    // MARK: - Header

    private var dateLine: String {
        var text = event.dateLabel
        if let doors = event.doorsTime, !doors.isEmpty {
            text += " · \(doors)"
        }
        return text
    }

    private func dayVenueLabel(_ dayVenue: DayVenue) -> String {
        guard let date = dayVenue.parsedDate else { return dayVenue.date }
        return Event.formatDayLabel(date)
    }

    // MARK: - Directions / ride row

    /// One row, equal thirds: Directions (outlined, Google Maps
    /// place-first link), Bolt (filled green, white text), inDrive
    /// (filled lime, dark text) — the apps' own Play Store icons at
    /// 18pt beside the name.
    private var rideRow: some View {
        HStack(spacing: 8) {
            if let directions = event.directionsURL {
                Button {
                    openURL(directions)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .font(.body)
                        Text("Directions")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            rideButton(.bolt)
            rideButton(.inDrive)
        }
    }

    private func rideButton(_ app: RideLauncher.RideApp) -> some View {
        Button {
            guard let rideAddress = event.rideAddress else { return }
            RideLauncher.launch(app, rideAddress: rideAddress) { message in
                toastCenter.show(message, duration: 2)
            }
        } label: {
            HStack(spacing: 5) {
                Image(app.iconName)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(app.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(rideBackground(app))
            .foregroundStyle(rideForeground(app))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(event.rideAddress == nil)
    }

    private func rideBackground(_ app: RideLauncher.RideApp) -> Color {
        switch app {
        case .bolt: return Color(red: 0x2A / 255, green: 0x9C / 255, blue: 0x64 / 255)
        case .inDrive: return Color(red: 0xC1 / 255, green: 0xF2 / 255, blue: 0x1D / 255)
        }
    }

    private func rideForeground(_ app: RideLauncher.RideApp) -> Color {
        switch app {
        case .bolt: return .white
        case .inDrive: return Color(red: 0x0C / 255, green: 0x0E / 255, blue: 0x0A / 255)
        }
    }

    // MARK: - Tickets

    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tickets — \(event.ticketStatus.label)")
                .font(.headline)
                .padding(.top, 14)
            if event.priceTiers.isEmpty {
                Text("Prices not published yet")
            } else {
                ForEach(event.priceTiers) { tier in
                    Text("• \(tier.display)")
                }
            }
            if let note = event.ticketNote, !note.isEmpty {
                Text(note)
                    .padding(.top, 6)
            }
            if let ticketURL = event.ticketURL {
                Button {
                    // Leave-app interstitial: warn first, like
                    // Instagram — the actual exit (and the ticket-tap
                    // metric) happens on Continue.
                    leaveApp = LeaveAppRequest(url: ticketURL, kind: .tickets)
                } label: {
                    Text("Get tickets")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Share / follow / attending

    private var shareButton: some View {
        Button(action: shareEvent) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share event")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func shareEvent() {
        let text = ShareService.shareText(for: event)
        metrics.recordShare(event.id)
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            var presenter = root
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                            y: presenter.view.bounds.midY,
                                            width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        }
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            HStack {
                Image(systemName: userStore.isFollowing(event) ? "bell.fill" : "bell")
                Text(userStore.isFollowing(event) ? "Following — alerts on" : "Follow for alerts")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func toggleFollow() {
        let wasFollowing = userStore.isFollowing(event)
        if !wasFollowing {
            metrics.recordFollow(event.id)
        }
        userStore.toggleFollow(event)
        Task {
            await eventStore.bumpFollowing(event: event, delta: wasFollowing ? -1 : 1)
        }
    }

    private func followingCountLine(_ count: Int) -> String {
        switch count {
        case 0: return "Nobody is following this event yet"
        case 1: return "1 user is following this event"
        default: return "\(count) users are following this event"
        }
    }

    private var attendingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Will you be attending?")
                .font(.headline)
                .padding(.top, 16)

            // Two segments, Yes / No; the selection is Yes while
            // attending and EMPTY otherwise — "No" is never shown as
            // selected. Tapping No removes the event from the
            // attending set (bump −1 when it was there). Tapping the
            // selected Yes again deselects it without a call (empty
            // selection allowed) — the store still holds the event,
            // so Yes shows selected again on the next render.
            HStack(spacing: 0) {
                attendingSegment(label: "Yes", systemImage: "checkmark", selected: userStore.isAttending(event)) {
                    if !userStore.isAttending(event) {
                        setAttending(going: true)
                    }
                }
                attendingSegment(label: "No", systemImage: "xmark", selected: false) {
                    setAttending(going: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )

            if let attendingCount {
                Text(attendingCountLine(attendingCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func attendingSegment(label: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func setAttending(going: Bool) {
        let wasGoing = userStore.isAttending(event)
        guard userStore.setAttending(event, going: going), wasGoing != going else { return }
        Task {
            await eventStore.bumpAttending(event: event, delta: going ? 1 : -1)
        }
    }

    private func attendingCountLine(_ count: Int) -> String {
        switch count {
        case 0: return "Nobody has tapped Yes yet"
        case 1: return "1 user has said they're attending"
        default: return "\(count) users have said they're attending"
        }
    }

    // MARK: - Sources & change history

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !event.sourceLinks.isEmpty {
                Text("Sources — tap to check for yourself:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                ForEach(event.sourceLinks, id: \.self) { raw in
                    if let url = URL(string: raw) {
                        Button {
                            // Source links exit through the same warning
                            // page as Get tickets, with source copy — no
                            // external link on this page drops the user
                            // straight out. The source-tap metric fires
                            // on Continue, when the exit happens.
                            leaveApp = LeaveAppRequest(url: url, kind: .source)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.caption)
                                Text(raw)
                                    .font(.caption)
                                    .underline()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("Sources: organiser direct contact (no public link)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }

            if let instagram = event.instagram?.organiser,
               let url = instagramURL(for: instagram) {
                Button {
                    leaveApp = LeaveAppRequest(url: url, kind: .source)
                } label: {
                    Text("Organiser on Instagram: \(instagram)")
                        .font(.caption)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func instagramURL(for handle: String) -> URL? {
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        return URL(string: "https://www.instagram.com/\(clean)")
    }

    private var sortedHistory: [ChangeLogEntry] {
        event.changeLog.sorted {
            ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast)
        }
    }

    private var changeHistorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                historyOpen.toggle()
            } label: {
                HStack {
                    Text("Change history")
                        .font(.headline)
                    Image(systemName: historyOpen ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            if historyOpen {
                ForEach(sortedHistory) { entry in
                    Text("• \(entry.displayDate) — \(entry.description)")
                        .font(.subheadline)
                }
            }
        }
    }
}

import SwiftUI

/// Full event page: flyer, details, price tiers, ticket link, attending
/// count, follow/share, sources and change log.
struct EventDetailView: View {
    let event: Event

    @EnvironmentObject private var userStore: UserStore
    @Environment(\.attendingService) private var attendingService
    @Environment(\.openURL) private var openURL

    @State private var isSharing = false

    private var attendingDelta: Int {
        userStore.attendingDelta(for: event)
    }

    /// Base feed count plus this device's local delta. Labelled as an
    /// estimate, exactly as the privacy policy describes it.
    private var displayedAttendingCount: Int? {
        guard let base = event.attendingCount else { return nil }
        return max(0, base + attendingDelta)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                flyerSection
                headerSection
                if event.unprovenPromoter {
                    unprovenBanner
                }
                detailsSection
                if !event.priceTiers.isEmpty {
                    ticketsSection
                }
                attendingSection
                if let description = event.description, !description.isEmpty {
                    descriptionSection(description)
                }
                sourcesSection
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    userStore.toggleFollow(event)
                } label: {
                    Image(systemName: userStore.isFollowing(event) ? "heart.fill" : "heart")
                        .foregroundStyle(userStore.isFollowing(event) ? .raveAccent : .primary)
                }
                .accessibilityLabel(userStore.isFollowing(event) ? "Unfollow" : "Follow")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    userStore.markShared(event)
                })
            }
        }
        .task {
            userStore.markViewed(event)
        }
    }

    // MARK: - Flyer

    private var flyerSection: some View {
        Group {
            if let url = event.flyerURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        flyerPlaceholder
                    case .empty:
                        ZStack {
                            flyerPlaceholder
                            ProgressView()
                        }
                    @unknown default:
                        flyerPlaceholder
                    }
                }
            } else {
                flyerPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.raveAccent.opacity(0.12))
    }

    private var flyerPlaceholder: some View {
        ZStack {
            Color.raveAccent.opacity(0.15)
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.raveAccent)
        }
        .frame(height: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.name)
                .font(.title2)
                .fontWeight(.bold)

            if let organiser = event.organiser {
                Text("by \(organiser)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let series = event.series {
                Text(series)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.raveAccent.opacity(0.15))
                    .foregroundStyle(.raveAccent)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Text(event.eventType.label)
                Text("·")
                Text(event.ticketStatus.label)
                if let age = event.ageLimit {
                    Text("·")
                    Text(age)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var unprovenBanner: some View {
        Label(
            "This promoter hasn’t been verified by the RaveWatchLagos team yet. Check the ticket link and sources before paying.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline)
        .padding()
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailRow(icon: "calendar", text: event.displayDate)
            if let doors = event.doorsTime, !doors.isEmpty {
                detailRow(icon: "clock", text: "Doors \(doors)")
            }
            if let place = event.placeLine {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.raveAccent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place)
                        if let address = event.address, !address.isEmpty {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let maps = event.mapsURL {
                            Link("Open in Apple Maps", destination: maps)
                                .font(.subheadline)
                        }
                    }
                }
            }
            if !event.genres.isEmpty {
                detailRow(icon: "music.note.list", text: event.genres.joined(separator: " · "))
            }
            if !event.djs.isEmpty {
                detailRow(icon: "waveform", text: "DJs: " + event.djs.joined(separator: ", "))
            }
        }
        .padding(.horizontal)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.raveAccent)
                .frame(width: 20)
            Text(text)
        }
    }

    // MARK: - Tickets

    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tickets")
                .font(.headline)

            ForEach(event.priceTiers) { tier in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.name)
                            .fontWeight(.medium)
                        if let note = tier.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(tier.priceNaira == 0 ? "Free" : Event.formatNaira(tier.priceNaira))
                        .fontWeight(.semibold)
                }
                Divider()
            }

            if let note = event.ticketNote, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if event.ticketStatus.canBuyTickets, let url = event.ticketURL {
                Link(destination: url) {
                    Text(event.ticketStatus.ticketButtonLabel)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.raveAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text("Ticket purchase happens on the organiser’s site, outside the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(event.ticketStatus.ticketButtonLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let url = event.ticketURL {
                    Link("View event page", destination: url)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Attending

    private var attendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Are you going?")
                .font(.headline)

            Picker("Are you going?", selection: attendingBinding) {
                Text("Yes").tag(AttendingOption.yes)
                Text("No").tag(AttendingOption.no)
                Text("—").tag(AttendingOption.none)
            }
            .pickerStyle(.segmented)

            if let count = displayedAttendingCount {
                Text("~\(count) going")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Attendance is an anonymous estimate — be the first to answer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Your answer is anonymous: only the event ID and a +1/−1 change are counted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private enum AttendingOption {
        case yes, no, none
    }

    private var attendingBinding: Binding<AttendingOption> {
        Binding(
            get: {
                switch userStore.attendingChoice(for: event) {
                case true: return .yes
                case false: return .no
                case nil: return .none
                }
            },
            set: { option in
                let choice: Bool? = switch option {
                case .yes: true
                case .no: false
                case .none: nil
                }
                Task {
                    let delta = userStore.setAttending(event, choice: choice)
                    await attendingService.sendAttendingChange(eventID: event.id, delta: delta)
                }
            }
        )
    }

    // MARK: - Description & sources

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text(text)
                .font(.body)
        }
        .padding(.horizontal)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources & updates")
                .font(.headline)

            if let verified = event.lastVerified, !verified.isEmpty {
                Text("Last verified \(verified)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let instagram = event.instagram?.organiser,
               let url = instagramURL(for: instagram) {
                Link("Organiser on Instagram: \(instagram)", destination: url)
                    .font(.subheadline)
            }

            ForEach(Array(event.sourceLinks.enumerated()), id: \.offset) { index, raw in
                if let url = URL(string: raw) {
                    Link(raw, destination: url)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            if !event.changeLog.isEmpty {
                Text("Change log")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(event.changeLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.description)
                            .font(.subheadline)
                    }
                }
            }

            if let url = Self.instagramProfileURL {
                Link("Report a problem · Instagram @ravewatchlagos",
                     destination: url)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
    }

    private static let instagramProfileURL = URL(string: "https://www.instagram.com/ravewatchlagos")

    private func instagramURL(for handle: String) -> URL? {
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        return URL(string: "https://www.instagram.com/\(clean)")
    }

    private var shareText: String {
        var text = "\(event.name) — \(event.displayDate)"
        if let place = event.placeLine {
            text += "\n\(place)"
        }
        if let price = event.priceSummary {
            text += "\n\(price)"
        }
        if let url = event.ticketURL {
            text += "\n\(url.absoluteString)"
        }
        return text
    }
}

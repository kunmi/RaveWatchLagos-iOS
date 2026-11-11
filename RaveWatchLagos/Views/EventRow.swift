import SwiftUI

/// One event in a list: flyer thumbnail, name, date + doors, place,
/// genre chips, price, ticket badge and a follow heart.
struct EventRow: View {
    let event: Event
    @EnvironmentObject private var userStore: UserStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            flyerThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(event.rowDateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let place = event.placeLine {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !event.genres.isEmpty {
                    genreChips
                }

                HStack(spacing: 8) {
                    if let price = event.priceSummary {
                        Text(price)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(event.isFree ? .green : .primary)
                    }
                    ticketBadge
                    Spacer()
                    followButton
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Flyer

    private var flyerThumbnail: some View {
        Group {
            if let url = event.flyerURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
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
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var flyerPlaceholder: some View {
        ZStack {
            Color.raveAccent.opacity(0.25)
            Image(systemName: "music.note")
                .foregroundStyle(.raveAccent)
        }
    }

    // MARK: - Chips & badge

    private var genreChips: some View {
        HStack(spacing: 4) {
            ForEach(Array(event.genres.prefix(3)), id: \.self) { genre in
                Text(genre)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.raveAccent.opacity(0.15))
                    .foregroundStyle(.raveAccent)
                    .clipShape(Capsule())
            }
            if event.genres.count > 3 {
                Text("+\(event.genres.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ticketBadge: some View {
        Text(event.ticketStatus.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch event.ticketStatus {
        case .ticketsOnSale: return .green
        case .soldOut: return .red
        case .ticketsSoon, .announced: return .orange
        case .unknown: return .secondary
        }
    }

    private var followButton: some View {
        Button {
            userStore.toggleFollow(event)
        } label: {
            Image(systemName: userStore.isFollowing(event) ? "heart.fill" : "heart")
                .foregroundStyle(userStore.isFollowing(event) ? .raveAccent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(userStore.isFollowing(event) ? "Unfollow \(event.name)" : "Follow \(event.name)")
    }
}

#Preview {
    List {
        EventRow(event: EventStorePreview.sampleEvent)
    }
    .environmentObject(UserStore())
}

private enum EventStorePreview {
    static var sampleEvent: Event {
        let json = """
        {
            "id": "303-garage-experiment-xvi-2026-11-12",
            "name": "303 GARAGE: Experiment XVI",
            "organiser": "Twlve.",
            "date": "2026-11-12",
            "doorsTime": "8 PM",
            "area": "Akoka",
            "address": "49 Lawani St, Akoka, Lagos",
            "genres": ["House", "Techno"],
            "eventType": "rave",
            "ticketStatus": "ticketsOnSale",
            "ticketLink": "https://getbookt.io/events/303-garage-experiment-xvi",
            "priceTiers": [{"name": "General Admission", "priceNaira": 3030, "note": null}],
            "unprovenPromoter": false,
            "sourceLinks": [],
            "lastVerified": "2026-11-10",
            "changeLog": []
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(Event.self, from: json)
    }
}

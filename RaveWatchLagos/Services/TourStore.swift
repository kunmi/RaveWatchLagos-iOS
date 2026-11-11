import Foundation

/// The first-launch tutorial's memory, ported from
/// `lib/services/tour_store.dart`: whether this phone has already seen
/// the coach-mark tour. Persisted like the other settings — preference
/// plus the settings-file mirror, so the tour shows exactly once and
/// not on every cold start after a storage hiccup. Also carries
/// Settings' "Replay the tutorial" request: the app shell listens for
/// `replayTick` changes and restarts the tour from step one.
@MainActor
final class TourStore: ObservableObject {
    private enum Key {
        static let seen = "ui.tourSeen"
    }

    @Published private(set) var seen = false
    @Published private(set) var replayTick = 0

    private let defaults: UserDefaults
    private let mirror = SettingsMirror()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.object(forKey: Key.seen) as? Bool {
            seen = saved
        } else if let mirrored = mirror.readAll()[Key.seen] as? Bool {
            seen = mirrored
            defaults.set(mirrored, forKey: Key.seen)
        }
    }

    func markSeen() {
        guard !seen else { return }
        seen = true
        defaults.set(true, forKey: Key.seen)
        mirror.writeKey(Key.seen, true)
        objectWillChange.send()
    }

    func requestReplay() {
        replayTick += 1
        objectWillChange.send()
    }
}

// MARK: - Tour steps

/// One step of the first-launch tour, ported verbatim from
/// `kTourSteps` in `lib/widgets/tour_overlay.dart` (Abatan's storyboard,
/// 2026-10-27: welcome → the card → the swipes → the filters → how
/// Following works, alerts included → how to remove from Following →
/// how Attending works → how to remove from Attending → share my picks
/// → the top corner).
enum TourAction {
    case none
    case feedSwipe
    case followingSwipe
    case attendingSwipe
    case sharePicks
    case themeToggle
}

/// Anchor names the tour spotlights. The views publish their frames to
/// `TourAnchorStore` under these names; a step with no mounted anchor
/// shows its caption centred instead of failing.
enum TourAnchor: String {
    case feedCard
    case feedFilters
    case feedTypeRow
    case feedTheme
    case feedSettings
    case followingBody
    case followingCard
    case followingInbox
    case attendingBody
    case attendingCard
    case attendingShare
}

struct TourStep {
    /// Bottom-bar index: 0 Following · 1 Feed · 2 Attending.
    let tab: Int
    let title: String
    let body: String
    /// The anchors to spotlight, in order.
    let anchors: [TourAnchor]
    /// Spotlighted only when NONE of `anchors` is mounted — a tab's
    /// body region, standing in for a first card or a share button
    /// that an empty list doesn't render yet.
    let fallback: TourAnchor?
    /// The hands-on action this step invites, if any. Action steps
    /// are OPTIONAL: doing the action advances the tour by itself,
    /// and tapping Next moves on without doing it.
    let action: TourAction
    /// The ONE control that stays live on this step — the overlay
    /// lets gestures through its rect while everything else stays
    /// blocked. Null = nothing is live.
    let actionTarget: TourAnchor?

    static let all: [TourStep] = [
        TourStep(
            tab: 1,
            title: "Welcome to RaveWatchLagos",
            body: "Every rave and DJ-led night in Lagos, updated daily. A quick tour — under a minute.",
            anchors: [], fallback: nil, action: .none, actionTarget: nil
        ),
        TourStep(
            tab: 1,
            title: "Every night at a glance",
            body: "Each card shows the date, venue, area and price — and where tickets are sold. Tap a card for the full details.",
            anchors: [.feedCard], fallback: nil, action: .none, actionTarget: .feedCard
        ),
        TourStep(
            tab: 1,
            title: "Swipe to keep a night",
            body: "Swipe right to Follow a night, swipe left to say you're Attending. The card stays in the feed either way.",
            anchors: [.feedCard], fallback: nil, action: .feedSwipe, actionTarget: .feedCard
        ),
        TourStep(
            tab: 1,
            title: "Narrow it down",
            body: "Filter by Area and Genre, or tap the calendar for Tonight, This weekend, This month and more.",
            anchors: [.feedFilters, .feedTypeRow], fallback: nil, action: .none, actionTarget: nil
        ),
        TourStep(
            tab: 0,
            title: "Your Following list",
            body: "Nights you follow collect here. Tap any card to open its full details.",
            anchors: [.followingBody], fallback: nil, action: .none, actionTarget: .followingCard
        ),
        TourStep(
            tab: 0,
            title: "Never miss a change",
            body: "When a followed night changes — tickets on sale, a new price, a venue announced — the alert lands here, grouped under the event.",
            anchors: [.followingInbox], fallback: nil, action: .none, actionTarget: nil
        ),
        TourStep(
            tab: 0,
            title: "Removing a night",
            body: "Swipe a card left to remove it from Following; swipe right to share it. Tapped by mistake? Undo brings it straight back.",
            anchors: [.followingCard], fallback: .followingBody, action: .followingSwipe, actionTarget: .followingCard
        ),
        TourStep(
            tab: 2,
            title: "Your Attending list",
            body: "The nights you're going to, in date order. This is the plan.",
            anchors: [.attendingBody], fallback: nil, action: .none, actionTarget: .attendingCard
        ),
        TourStep(
            tab: 2,
            title: "Changing the plan",
            body: "Swipe left to take a night off your list — the count on its card drops with it. Swipe right to share it; Undo restores it if you slip.",
            anchors: [.attendingCard], fallback: .attendingBody, action: .attendingSwipe, actionTarget: .attendingCard
        ),
        TourStep(
            tab: 2,
            title: "Share your picks",
            body: "This button sends your whole Attending list as one message — the easy way to rally your people.",
            anchors: [.attendingShare], fallback: .attendingBody, action: .none, actionTarget: nil
        ),
        TourStep(
            tab: 1,
            title: "Night, light & settings",
            body: "The sun and moon switch between night and light. The gear opens Settings. That's everything — see you out there.",
            anchors: [.feedTheme, .feedSettings], fallback: nil, action: .none, actionTarget: nil
        ),
    ]
}

// MARK: - Tour demo events

/// The tour's example cards, ported from
/// `lib/services/tour_demo_events.dart`. They are never written to the
/// stores and vanish when the tour ends, so an empty Following or
/// Attending list still has something real for the tour to point at.
enum TourDemoEvents {
    static func demoEvents() -> [Event] {
        let calendar = Event.lagosCalendar
        let today = calendar.startOfDay(for: Date())
        let day3 = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let day6 = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return [
            makeEvent(
                id: "tour-demo-beach-rave",
                name: "Example Beach Rave",
                area: "Lekki",
                genres: ["House", "Afro Tech"],
                ageLimit: "18+",
                entryPrice: 7500,
                ticketStatus: .ticketsOnSale,
                attendingCount: 23,
                followingCount: 14,
                date: formatter.string(from: day3)
            ),
            makeEvent(
                id: "tour-demo-rooftop-party",
                name: "Example Rooftop Party",
                area: "Victoria Island",
                genres: ["Afrobeats", "Amapiano"],
                ageLimit: "21+",
                entryPrice: 5000,
                ticketStatus: .announced,
                attendingCount: 9,
                followingCount: 6,
                date: formatter.string(from: day6)
            ),
        ]
    }

    private static func makeEvent(
        id: String, name: String, area: String, genres: [String],
        ageLimit: String, entryPrice: Int, ticketStatus: TicketStatus,
        attendingCount: Int, followingCount: Int, date: String
    ) -> Event {
        // Decoded from JSON so the demo events go through the same
        // tolerant parsing as real feed events.
        let json = """
        {
            "id": "\(id)",
            "name": "\(name)",
            "organiser": "Example Collective",
            "date": "\(date)",
            "doorsTime": "9 PM",
            "venueName": "Example Venue",
            "area": "\(area)",
            "genres": [\(genres.map { "\"\($0)\"" }.joined(separator: ", "))],
            "eventType": "rave",
            "ageLimit": "\(ageLimit)",
            "ticketStatus": "\(ticketStatus.rawValue)",
            "priceTiers": [{"name": "General Admission", "priceNaira": \(entryPrice)}],
            "unprovenPromoter": false,
            "sourceLinks": [],
            "lastVerified": "\(date)",
            "changeLog": [],
            "attendingCount": \(attendingCount),
            "followingCount": \(followingCount)
        }
        """
        // The JSON above is built from fixed literals; a decode failure
        // here would be a programmer error, surfaced loudly in debug.
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(Event.self, from: data)
    }
}

import Foundation
import SwiftUI

/// The user's on-device theme choice. Night is the default: this is a
/// nightlife app and the feed is read mostly after dark.
enum AppTheme: String, CaseIterable, Codable {
    case night
    case light
    case system

    var label: String {
        switch self {
        case .night: return "Night"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .night: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Everything the app remembers about the user lives here, on the device
/// only (UserDefaults). Nothing in this store ever leaves the phone — see
/// PrivacyPolicyView and the data repo's privacy-policy.html.
@MainActor
final class UserStore: ObservableObject {
    // MARK: Keys

    private enum Key {
        static let followed = "ravewatchlagos.followedEventIDs"
        static let attending = "ravewatchlagos.attendingState"
        static let theme = "ravewatchlagos.theme"
        static let eventsViewed = "ravewatchlagos.stats.eventsViewed"
        static let eventsShared = "ravewatchlagos.stats.eventsShared"
    }

    // MARK: State

    @Published private(set) var followedEventIDs: Set<String> = []
    /// true = attending (counts as +1), false = not attending (counts as −1).
    /// Absent = no answer given. Mirrors the privacy policy: a tap sends only
    /// the event ID and a +1/−1 change — see AttendingService.
    @Published private(set) var attendingState: [String: Bool] = [:]
    @Published var theme: AppTheme = .night {
        didSet { saveTheme() }
    }
    @Published private(set) var eventsViewedCount = 0
    @Published private(set) var eventsSharedCount = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        followedEventIDs = Set(defaults.stringArray(forKey: Key.followed) ?? [])
        if let data = defaults.data(forKey: Key.attending),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            attendingState = decoded
        }
        if let raw = defaults.string(forKey: Key.theme),
           let stored = AppTheme(rawValue: raw) {
            theme = stored
        }
        eventsViewedCount = defaults.integer(forKey: Key.eventsViewed)
        eventsSharedCount = defaults.integer(forKey: Key.eventsShared)
    }

    // MARK: - Following

    func isFollowing(_ event: Event) -> Bool {
        followedEventIDs.contains(event.id)
    }

    func toggleFollow(_ event: Event) {
        if followedEventIDs.contains(event.id) {
            followedEventIDs.remove(event.id)
        } else {
            followedEventIDs.insert(event.id)
        }
        defaults.set(Array(followedEventIDs), forKey: Key.followed)
    }

    var followedCount: Int { followedEventIDs.count }

    // MARK: - Attending

    /// The local delta this device contributes to an event's attending total:
    /// +1 while attending, −1 while explicitly not attending, 0 otherwise.
    func attendingDelta(for event: Event) -> Int {
        switch attendingState[event.id] {
        case true: return 1
        case false: return -1
        case nil: return 0
        }
    }

    func attendingChoice(for event: Event) -> Bool? {
        attendingState[event.id]
    }

    /// Records the user's answer and returns the delta to report.
    /// Pass `nil` to clear a previous answer.
    @discardableResult
    func setAttending(_ event: Event, choice: Bool?) -> Int {
        let previous = attendingDelta(for: event)
        if let choice {
            attendingState[event.id] = choice
        } else {
            attendingState.removeValue(forKey: event.id)
        }
        saveAttending()
        return attendingDelta(for: event) - previous
    }

    private func saveAttending() {
        if let data = try? JSONEncoder().encode(attendingState) {
            defaults.set(data, forKey: Key.attending)
        }
    }

    var attendingYesCount: Int {
        attendingState.values.filter { $0 }.count
    }

    // MARK: - Usage stats (on-device only)

    func markViewed(_ event: Event) {
        eventsViewedCount += 1
        defaults.set(eventsViewedCount, forKey: Key.eventsViewed)
    }

    func markShared(_ event: Event) {
        eventsSharedCount += 1
        defaults.set(eventsSharedCount, forKey: Key.eventsShared)
    }

    // MARK: - Theme

    private func saveTheme() {
        defaults.set(theme.rawValue, forKey: Key.theme)
    }
}

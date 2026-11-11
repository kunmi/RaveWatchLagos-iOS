import Foundation
import SwiftUI

/// The user's on-device theme choice. Night is the default: this is a
/// nightlife app and the feed is read mostly after dark.
///
/// The Flutter app toggles night/light only (`ui.themeMode`, "dark" /
/// "light"). iOS adds "system" as a third choice — an iOS-appropriate
/// extension, stored under the same key.
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

    /// The value stored under `ui.themeMode` ("dark" / "light" /
    /// "system" — the first two match the Flutter app's values).
    var storedValue: String {
        switch self {
        case .night: return "dark"
        case .light: return "light"
        case .system: return "system"
        }
    }

    init(storedValue: String) {
        switch storedValue {
        case "light": self = .light
        case "system": self = .system
        default: self = .night
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
/// only. Nothing in this store ever leaves the phone — see
/// PrivacyPolicyView and the data repo's privacy-policy.html.
///
/// Followed and attending events are persisted like the Flutter app's
/// `FollowStore` / `AttendingStore`: a triple-redundant id set
/// (preference string + file mirror + legacy recovery), keyed
/// `follow.events` / `attending.events`.
///
/// Attending is a SET of event ids, exactly as in Flutter — there is no
/// "explicit No" state. The detail page's Yes/No control shows Yes
/// selected while the event is in the set; tapping No removes it
/// (bump −1 when it was there). This replaces the v1 three-state
/// `[String: Bool]` model, which counted a "No" as −1 — a state the
/// Android app never had.
@MainActor
final class UserStore: ObservableObject {
    // MARK: Keys

    private enum Key {
        static let theme = "ui.themeMode"
    }

    // MARK: State

    @Published private(set) var followedEventIDs: Set<String> = []
    @Published private(set) var attendingEventIDs: Set<String> = []
    @Published var theme: AppTheme = .night {
        didSet { saveTheme() }
    }

    private let followStore: PersistedIdSet
    private let attendingStore: PersistedIdSet
    private let defaults: UserDefaults
    private let mirror = SettingsMirror()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        followStore = PersistedIdSet(key: "follow.events", fileName: "follow_events.json", defaults: defaults)
        attendingStore = PersistedIdSet(key: "attending.events", fileName: "attending_events.json", defaults: defaults)
        followedEventIDs = followStore.load()
        attendingEventIDs = attendingStore.load()
        if let raw = defaults.string(forKey: Key.theme) {
            theme = AppTheme(storedValue: raw)
        } else if let mirrored = mirror.readAll()[Key.theme] as? String {
            theme = AppTheme(storedValue: mirrored)
            defaults.set(mirrored, forKey: Key.theme)
        }
    }

    // MARK: - Following

    func isFollowing(_ event: Event) -> Bool {
        followedEventIDs.contains(event.id)
    }

    /// Toggles the follow and returns the new state (true = following).
    /// A follow records a metric; the caller bumps the shared count.
    @discardableResult
    func toggleFollow(_ event: Event) -> Bool {
        let nowFollowing: Bool
        if followedEventIDs.contains(event.id) {
            followedEventIDs.remove(event.id)
            nowFollowing = false
        } else {
            followedEventIDs.insert(event.id)
            nowFollowing = true
        }
        followStore.save(followedEventIDs)
        objectWillChange.send()
        return nowFollowing
    }

    var followedCount: Int { followedEventIDs.count }

    // MARK: - Attending

    func isAttending(_ event: Event) -> Bool {
        attendingEventIDs.contains(event.id)
    }

    /// Sets the attending state. Returns true when the set changed —
    /// the caller bumps the shared count by +1 (going) or −1 (not
    /// going) only then, exactly as the Flutter detail page does.
    @discardableResult
    func setAttending(_ event: Event, going: Bool) -> Bool {
        let changed: Bool
        if going {
            changed = attendingEventIDs.insert(event.id).inserted
        } else {
            changed = attendingEventIDs.remove(event.id) != nil
        }
        if changed {
            attendingStore.save(attendingEventIDs)
            objectWillChange.send()
        }
        return changed
    }

    var attendingYesCount: Int { attendingEventIDs.count }

    // MARK: - Theme

    /// The app-bar toggle: night ↔ light. (System is chosen in Settings.)
    func toggleTheme() {
        theme = theme == .night ? .light : .night
    }

    private func saveTheme() {
        defaults.set(theme.storedValue, forKey: Key.theme)
        mirror.writeKey(Key.theme, theme.storedValue)
    }
}

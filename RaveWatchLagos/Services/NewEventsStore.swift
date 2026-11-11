import Foundation

/// The "new" card markers, ported from `lib/services/new_events_store.dart`.
///
/// Three id sets, persisted like the other stores (preference + file
/// mirror, union on load):
/// - knownIds: every id the phone has already shown (capped at 400).
/// - unreadIds: ids shown but not yet opened — the violet left bar.
/// - latestAdds: the latest edition's adds — the "Just added" pill.
///   Edition-pinned: opening an event does NOT remove it from the pill.
///
/// Rules, as in the Flutter store:
/// - The first feed seeds silently (nothing is "new" on first install).
/// - Syncs are skipped while the repository shows the bundled seed —
///   otherwise a first install seeds "known" with the seed ids and the
///   whole live feed reads as new.
/// - Ids that left the feed are pruned.
@MainActor
final class NewEventsStore: ObservableObject {
    private enum Key {
        static let known = "newEvents.knownIds"
        static let unread = "newEvents.unreadIds"
        static let latestAdds = "newEvents.latestAdds"
    }

    private static let knownCap = 400

    @Published private(set) var unreadIDs: Set<String> = []
    @Published private(set) var latestAddIDs: Set<String> = []

    private var knownIDs: Set<String> = []

    private let knownStore: PersistedIdSet
    private let unreadStore: PersistedIdSet
    private let latestStore: PersistedIdSet
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        knownStore = PersistedIdSet(key: Key.known, fileName: "new_events_known.json", defaults: defaults)
        unreadStore = PersistedIdSet(key: Key.unread, fileName: "new_events_unread.json", defaults: defaults)
        latestStore = PersistedIdSet(key: Key.latestAdds, fileName: "new_events_latest.json", defaults: defaults)
        knownIDs = knownStore.load()
        unreadIDs = unreadStore.load()
        latestAddIDs = latestStore.load()
    }

    /// The violet left bar: shown but not yet opened.
    func isNew(_ eventID: String) -> Bool { unreadIDs.contains(eventID) }

    /// In the latest edition's adds — the "Just added" pill. Opening
    /// the event does not remove it.
    func isJustAdded(_ eventID: String) -> Bool { latestAddIDs.contains(eventID) }

    /// Opening an event clears its violet bar (but not its Just-added
    /// membership).
    func markRead(_ eventID: String) {
        guard unreadIDs.contains(eventID) else { return }
        unreadIDs.remove(eventID)
        unreadStore.save(unreadIDs)
        objectWillChange.send()
    }

    /// Diffs a freshly applied feed against the ids this phone has
    /// already shown. Skipped while showing the bundled seed.
    func syncWithFeed(_ events: [Event], isBundledSeed: Bool) {
        guard !isBundledSeed else { return }
        let feedIDs = Set(events.map(\.id))

        if knownIDs.isEmpty {
            // First feed: seed silently — nothing is "new" on first install.
            knownIDs = feedIDs
            knownStore.save(knownIDs)
            return
        }

        let added = feedIDs.subtracting(knownIDs)
        if !added.isEmpty {
            unreadIDs.formUnion(added)
            unreadStore.save(unreadIDs)
            latestAddIDs = added
            latestStore.save(latestAddIDs)
        } else {
            // No new ids — but prune latestAdds to ids still in the feed.
            latestAddIDs.formIntersection(feedIDs)
            latestStore.save(latestAddIDs)
        }

        // Prune ids that left the feed.
        unreadIDs.formIntersection(feedIDs)
        unreadStore.save(unreadIDs)

        knownIDs.formUnion(feedIDs)
        if knownIDs.count > Self.knownCap {
            // Cap at 400: keep the ids still in the feed, drop the oldest
            // rest (insertion order is not tracked — drop arbitrary extras).
            var kept = knownIDs.intersection(feedIDs)
            if kept.count > Self.knownCap {
                kept = Set(kept.prefix(Self.knownCap))
            }
            knownIDs = kept
        }
        knownStore.save(knownIDs)
        objectWillChange.send()
    }
}

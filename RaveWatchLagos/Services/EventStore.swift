import Foundation

/// The feed's freshness — TWO states only, as in the Flutter app:
/// green = the app holds the latest sweep edition, grey = it doesn't.
/// The feed is a DAILY edition, published by a sweep at 01:00 Lagos
/// time (00:00 UTC); an edition stamped yesterday whose successor
/// isn't due yet IS the latest.
enum FeedFreshness {
    case latest
    case behind
}

/// Loads the RaveWatchLagos event feed.
///
/// Strategy, as in the Flutter `EventRepository`: live feed → on-device
/// cache (`events_feed_cache_v1`) → bundled seed. `sourceLabel` is
/// Live / Saved copy / Built-in. Parsing is tolerant (skip broken
/// records, coerce instead of crash).
///
/// Live feed: https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json
/// Bundled snapshot: Resources/events.json (generated 2026-11-10).
///
/// Live attending/following totals overlay the feed-published counts on
/// the cards (the published counts can be a day old). The overlay is
/// re-applied on every feed load, so the order of the two fetches does
/// not matter. A failed count fetch keeps the feed values; a failed
/// bump falls back to local arithmetic — a locally-applied tap on a
/// failed bump is acceptable, per the Flutter app's v1.9 audit note.
@MainActor
final class EventStore: ObservableObject {
    static let feedURLString = "https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json"
    private static let cacheKey = "events_feed_cache_v1"
    private static let refreshTimeout: TimeInterval = 15

    @Published private(set) var events: [Event] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var sourceLabel = "Built-in"

    /// Live totals from Supabase, overlaid on the feed-published counts.
    @Published private(set) var liveAttendingCounts: [String: Int] = [:]
    @Published private(set) var liveFollowingCounts: [String: Int] = [:]

    /// When the last feed fetch was kicked off (init or a resume
    /// refetch). The feed is a DAILY edition: without a resume refetch,
    /// an app process that stays alive across the nightly publish keeps
    /// showing the old edition indefinitely. Throttled so brief app
    /// switches (back from a ticket page, a notification glance) don't
    /// refetch.
    private(set) var lastFetchKick = Date()
    static let resumeRefetchGap: TimeInterval = 15 * 60

    var newEventsStore: NewEventsStore?

    private let attendingService: AttendingService
    private let attendingCounts = SupabaseAttendingCounts()
    private let followingCounts = SupabaseFollowingCounts()
    private let defaults: UserDefaults

    private var hasLoadedBundled = false

    init(attendingService: AttendingService = SupabaseAttendingService(),
         defaults: UserDefaults = .standard) {
        self.attendingService = attendingService
        self.defaults = defaults
    }

    // MARK: - Loading

    /// Loads the bundled snapshot (if not already loaded), then refreshes
    /// from the network.
    func load() async {
        loadBundled()
        await refresh()
        await syncCounts()
    }

    /// Loads the bundled snapshot as the offline fallback.
    func loadBundled() {
        guard !hasLoadedBundled else { return }
        hasLoadedBundled = true
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else {
            lastError = "Bundled event list is missing."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let feed = try JSONDecoder().decode(FeedResponse.self, from: data)
            apply(feed, source: .bundled)
        } catch {
            lastError = "Could not read the bundled event list."
        }
    }

    /// Fetches the live feed. On failure the saved copy (or bundled
    /// events) stay on screen and `lastError` is set so the UI can
    /// offer a retry.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = events.isEmpty
        defer {
            isRefreshing = false
            isLoading = false
        }
        lastFetchKick = Date()
        do {
            let data = try await fetchFeedData()
            let feed = try JSONDecoder().decode(FeedResponse.self, from: data)
            apply(feed, source: .live)
            lastError = nil
            // Persist the live feed as the saved copy.
            defaults.set(String(data: data, encoding: .utf8), forKey: Self.cacheKey)
        } catch {
            // Fall back to the saved copy when the live fetch fails.
            if let cached = defaults.string(forKey: Self.cacheKey),
               let data = cached.data(using: .utf8),
               let feed = try? JSONDecoder().decode(FeedResponse.self, from: data) {
                apply(feed, source: .savedCopy)
                lastError = "Couldn’t update the event list. Showing the last saved list."
            } else {
                lastError = "Couldn’t update the event list. Showing the bundled list."
            }
        }
    }

    /// Resume refetch: called when the app returns to the foreground.
    /// Refetches only when more than 15 minutes passed since the last
    /// fetch kick, then re-overlays the live counts.
    func resumeRefetchIfNeeded() async {
        guard Date().timeIntervalSince(lastFetchKick) >= Self.resumeRefetchGap else { return }
        await refresh()
        await syncCounts()
    }

    private func fetchFeedData() async throws -> Data {
        guard let url = URL(string: Self.feedURLString) else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.refreshTimeout
        configuration.timeoutIntervalForResource = Self.refreshTimeout
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private enum Source { case bundled, savedCopy, live }

    private func apply(_ feed: FeedResponse, source: Source) {
        // Sort by start date, then name. Events with an unparseable date go last.
        events = feed.events.sorted { lhs, rhs in
            switch (lhs.startDate, rhs.startDate) {
            case let (a?, b?): return a != b ? a < b : lhs.name < rhs.name
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
        switch source {
        case .live:
            sourceLabel = "Live"
            if let generatedAt = feed.generatedAt,
               let date = ISO8601DateFormatter().date(from: generatedAt) {
                lastUpdated = date
            }
        case .savedCopy:
            sourceLabel = "Saved copy"
            if let generatedAt = feed.generatedAt,
               let date = ISO8601DateFormatter().date(from: generatedAt) {
                lastUpdated = date
            }
        case .bundled:
            sourceLabel = "Built-in"
        }
        // Diff the feed against the ids this phone has already shown —
        // skipped while showing the bundled seed.
        newEventsStore?.syncWithFeed(events, isBundledSeed: source == .bundled)
        objectWillChange.send()
    }

    // MARK: - Freshness

    var freshness: FeedFreshness {
        Self.feedFreshness(generatedAt: lastUpdated, now: Date())
    }

    /// The header's "updated Oct 22, 2026" text: the feed stamp
    /// converted to the phone's LOCAL time, year included.
    var updatedLabel: String? {
        guard let lastUpdated else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let calendar = Calendar.current
        return "updated \(months[calendar.component(.month, from: lastUpdated) - 1]) \(calendar.component(.day, from: lastUpdated)), \(calendar.component(.year, from: lastUpdated))"
    }

    /// The status line under the filters: source label (if not Live) •
    /// updated label • "new edition daily" if behind • "checking for
    /// updates…" if refreshing. The 'Live' word is gone — the coloured
    /// freshness dot says it now.
    var statusLine: String {
        var parts: [String] = []
        if sourceLabel != "Live" { parts.append(sourceLabel) }
        if let updatedLabel { parts.append(updatedLabel) }
        if freshness == .behind { parts.append("new edition daily") }
        if isRefreshing { parts.append("checking for updates…") }
        return parts.joined(separator: " • ")
    }

    static func feedFreshness(generatedAt: Date?, now: Date) -> FeedFreshness {
        guard let generatedAt else { return .behind }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let stampDay = calendar.startOfDay(for: generatedAt)
        if stampDay >= today { return .latest }
        return editionStillCurrent(stampUTC: generatedAt, nowUTC: now) ? .latest : .behind
    }

    /// Whether the edition a stamp belongs to is still the latest one
    /// due. Editions publish daily at 00:00 UTC (01:00 Lagos); an
    /// edition stamped in the UTC day starting at cycleStart is current
    /// until the NEXT edition's instant plus a 1-hour grace
    /// (cycleStart + 25h). Pure instant math — timezone-independent.
    static func editionStillCurrent(stampUTC: Date, nowUTC: Date) -> Bool {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cycleStart = utcCalendar.startOfDay(for: stampUTC)
        let missedAt = cycleStart.addingTimeInterval(25 * 60 * 60)
        return nowUTC < missedAt
    }

    // MARK: - Derived data

    /// Events not yet over. A multi-day event counts until its LAST day:
    /// it stays listed while it is still running, and retires the day
    /// after it ends.
    var upcomingEvents: [Event] {
        let calendar = Event.lagosCalendar
        let today = calendar.startOfDay(for: Date())
        return events.filter { event in
            calendar.startOfDay(for: event.lastDay) >= today
        }
    }

    /// All areas present in the current feed, sorted, with "All areas" first.
    var allAreas: [String] {
        let found = Array(Set(upcomingEvents.compactMap(\.area))).sorted()
        return ["All areas"] + found
    }

    /// All genres present in the current feed, sorted, with "All genres" first.
    var allGenres: [String] {
        let found = Array(Set(upcomingEvents.flatMap(\.genres))).sorted()
        return ["All genres"] + found
    }

    func event(withID id: String) -> Event? {
        events.first { $0.id == id }
    }

    // MARK: - Live counts

    /// The displayed attending total: the live Supabase total when
    /// known, else the feed-published count. Nil when neither exists —
    /// the count line is then hidden ("count unknown").
    func attendingCount(for event: Event) -> Int? {
        liveAttendingCounts[event.id] ?? event.attendingCount
    }

    /// The displayed following total, same rule as attending.
    func followingCount(for event: Event) -> Int? {
        liveFollowingCounts[event.id] ?? event.followingCount
    }

    /// Overlays live totals on the feed-published counts. Fresher wins:
    /// a live total always replaces the feed value. Re-applied on every
    /// feed load, so the order of the two fetches does not matter.
    func applyAttendingCounts(_ counts: [String: Int]) {
        for (id, count) in counts {
            liveAttendingCounts[id] = count
        }
        objectWillChange.send()
    }

    func applyFollowingCounts(_ counts: [String: Int]) {
        for (id, count) in counts {
            liveFollowingCounts[id] = count
        }
        objectWillChange.send()
    }

    /// Fetches all counters in one request per table and overlays them.
    /// Null results keep the feed values.
    func syncCounts() async {
        if let all = await attendingCounts.fetchAllCounts() {
            applyAttendingCounts(all)
        }
        if let following = await followingCounts.fetchAllCounts() {
            applyFollowingCounts(following)
        }
    }

    /// Per-event fetch (the detail page's init): fresher wins, feed
    /// fallback. Null keeps the current value.
    func fetchCounts(for event: Event) async {
        if let count = await attendingCounts.fetchCount(eventID: event.id) {
            liveAttendingCounts[event.id] = count
            objectWillChange.send()
        }
        if let count = await followingCounts.fetchCount(eventID: event.id) {
            liveFollowingCounts[event.id] = count
            objectWillChange.send()
        }
    }

    /// Bumps the attending counter by `delta` (+1 / −1) and returns the
    /// new total. On failure, applies the delta locally (clamped at 0)
    /// and propagates that — a locally-applied tap on a failed bump is
    /// acceptable, and the store's own answer never rolls back.
    @discardableResult
    func bumpAttending(event: Event, delta: Int) async -> Int? {
        if let updated = await attendingService.sendAttendingChange(eventID: event.id, delta: delta) {
            liveAttendingCounts[event.id] = updated
            objectWillChange.send()
            return updated
        }
        if let current = attendingCount(for: event) {
            let total = max(0, current + delta)
            liveAttendingCounts[event.id] = total
            objectWillChange.send()
            return total
        }
        return nil
    }

    /// Bumps the following counter by `delta`, same fallback as attending.
    @discardableResult
    func bumpFollowing(event: Event, delta: Int) async -> Int? {
        if let updated = await followingCounts.bump(eventID: event.id, delta: delta) {
            liveFollowingCounts[event.id] = updated
            objectWillChange.send()
            return updated
        }
        if let current = followingCount(for: event) {
            let total = max(0, current + delta)
            liveFollowingCounts[event.id] = total
            objectWillChange.send()
            return total
        }
        return nil
    }
}

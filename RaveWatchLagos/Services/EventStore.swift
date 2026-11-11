import Foundation

/// Loads the RaveWatchLagos event feed.
///
/// Strategy: show the bundled snapshot immediately (so the app works
/// offline on first launch), then fetch the live feed from GitHub in the
/// background. If the live fetch fails, the bundled events stay on screen
/// and the error is surfaced non-fatally for pull-to-refresh to retry.
///
/// Live feed: https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json
/// Bundled snapshot: Resources/events.json (generated 2026-11-10).
@MainActor
final class EventStore: ObservableObject {
    static let feedURLString = "https://raw.githubusercontent.com/fabat01/ravewatchlagos-data/main/events.json"

    @Published private(set) var events: [Event] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    private var hasLoadedBundled = false

    // MARK: - Loading

    /// Loads the bundled snapshot (if not already loaded), then refreshes
    /// from the network.
    func load() async {
        loadBundled()
        await refresh()
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

    /// Fetches the live feed. On failure the current events are kept and
    /// `lastError` is set so the UI can offer a retry.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await fetchFeedData()
            let feed = try JSONDecoder().decode(FeedResponse.self, from: data)
            apply(feed, source: .live)
            lastError = nil
        } catch {
            lastError = "Couldn’t update the event list. Showing the last saved list."
        }
    }

    private func fetchFeedData() async throws -> Data {
        guard let url = URL(string: Self.feedURLString) else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private enum Source { case bundled, live }

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
        if source == .live {
            if let generatedAt = feed.generatedAt,
               let date = ISO8601DateFormatter().date(from: generatedAt) {
                lastUpdated = date
            } else {
                lastUpdated = Date()
            }
        }
    }

    // MARK: - Derived data

    /// Events grouped by day, in date order, for the Discover list.
    var eventsByDay: [(day: Date, events: [Event])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate ?? .distantFuture)
        }
        return grouped.keys.sorted().map { day in
            (day: day, events: grouped[day] ?? [])
        }
    }

    /// All genres present in the current feed, sorted by frequency.
    var allGenres: [String] {
        var counts: [String: Int] = [:]
        for event in events {
            for genre in event.genres {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// All areas present in the current feed, alphabetically.
    var allAreas: [String] {
        Array(Set(events.compactMap(\.area))).sorted()
    }

    func event(withID id: String) -> Event? {
        events.first { $0.id == id }
    }
}

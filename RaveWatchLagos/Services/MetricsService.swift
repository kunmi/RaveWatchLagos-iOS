import Foundation

/// On-device usage counts, ported from `lib/services/metrics_service.dart`.
///
/// Stored under the key `metrics.counts.v1` as JSON
/// `{eventId: {opens, ticketTaps, sourceTaps, follows, shares}}`.
/// Everything stays on the phone — the counts are never uploaded. The
/// Android app collects them but shows them nowhere; this port does the
/// same (the v1 "You" tab's usage summary had no Android counterpart
/// and was removed — see README).
@MainActor
final class MetricsService: ObservableObject {
    private enum Key {
        static let counts = "metrics.counts.v1"
    }

    struct EventMetrics: Codable {
        var opens = 0
        var ticketTaps = 0
        var sourceTaps = 0
        var follows = 0
        var shares = 0
    }

    @Published private(set) var counts: [String: EventMetrics] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.counts),
           let decoded = try? JSONDecoder().decode([String: EventMetrics].self, from: data) {
            counts = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(counts) {
            defaults.set(data, forKey: Key.counts)
        }
    }

    private func bump(_ eventID: String, _ change: (inout EventMetrics) -> Void) {
        var metrics = counts[eventID] ?? EventMetrics()
        change(&metrics)
        counts[eventID] = metrics
        save()
    }

    func recordOpen(_ eventID: String) { bump(eventID) { $0.opens += 1 } }
    func recordTicketTap(_ eventID: String) { bump(eventID) { $0.ticketTaps += 1 } }
    func recordSourceTap(_ eventID: String) { bump(eventID) { $0.sourceTaps += 1 } }
    func recordFollow(_ eventID: String) { bump(eventID) { $0.follows += 1 } }
    func recordShare(_ eventID: String) { bump(eventID) { $0.shares += 1 } }

    func metrics(for eventID: String) -> EventMetrics {
        counts[eventID] ?? EventMetrics()
    }

    /// Totals across all events, per metric.
    func totals() -> EventMetrics {
        counts.values.reduce(into: EventMetrics()) { total, entry in
            total.opens += entry.opens
            total.ticketTaps += entry.ticketTaps
            total.sourceTaps += entry.sourceTaps
            total.follows += entry.follows
            total.shares += entry.shares
        }
    }
}

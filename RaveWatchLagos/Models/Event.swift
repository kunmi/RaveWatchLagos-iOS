import Foundation

// MARK: - Feed

/// Top-level shape of events.json from the RaveWatchLagos data repo.
struct FeedResponse: Decodable {
    let events: [Event]
    let generatedAt: String?
}

// MARK: - Price tier

struct PriceTier: Codable, Identifiable, Hashable {
    var id: String { name }

    let name: String
    let priceNaira: Int
    let note: String?

    init(name: String, priceNaira: Int, note: String? = nil) {
        self.name = name
        self.priceNaira = priceNaira
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Defensive: a tier without a price is treated as unknown (0) rather
        // than failing the whole feed decode.
        priceNaira = try container.decodeIfPresent(Int.self, forKey: .priceNaira) ?? 0
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - Change log

struct ChangeLogEntry: Codable, Identifiable, Hashable {
    var id: String { date + description }

    /// Raw date string from the feed: "yyyy-MM-dd" or an ISO-8601 datetime.
    let date: String
    let description: String
}

// MARK: - Instagram links

/// The feed's `instagram` field is an object, e.g. {"organiser": "@wearedisturbinggidi"}.
struct InstagramLinks: Codable, Hashable {
    let organiser: String?
}

// MARK: - Event type / ticket status

enum EventType: String, Codable, CaseIterable {
    case club
    case rave
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = EventType(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .club: return "Club"
        case .rave: return "Rave"
        case .unknown: return "Event"
        }
    }
}

enum TicketStatus: String, Codable {
    case ticketsOnSale
    case announced
    case ticketsSoon
    case soldOut
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = TicketStatus(rawValue: raw) ?? .unknown
    }

    /// Short badge label shown on rows and the detail screen.
    var label: String {
        switch self {
        case .ticketsOnSale: return "Tickets on sale"
        case .announced: return "Announced"
        case .ticketsSoon: return "Tickets soon"
        case .soldOut: return "Sold out"
        case .unknown: return "Details TBA"
        }
    }

    /// Whether a ticket link can currently lead to a purchase.
    var canBuyTickets: Bool { self == .ticketsOnSale }

    /// Honest label for the ticket button when buying is not possible.
    var ticketButtonLabel: String {
        switch self {
        case .ticketsOnSale: return "Get tickets"
        case .announced: return "Announced — no tickets yet"
        case .ticketsSoon: return "Tickets coming soon"
        case .soldOut: return "Sold out"
        case .unknown: return "Tickets TBA"
        }
    }
}

// MARK: - Event

/// One event from the RaveWatchLagos feed.
///
/// Decoding is deliberately tolerant: unknown keys in the feed (e.g. stray
/// "_cl" keys) are ignored, and every field except `id`, `name` and `date`
/// has a safe default so one malformed event never breaks the whole feed.
struct Event: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let organiser: String?
    let series: String?
    /// Raw date string: "yyyy-MM-dd" or an ISO-8601 datetime.
    let date: String
    /// Raw end-date string for multi-day events, same formats as `date`.
    let endDate: String?
    let doorsTime: String?
    let venueName: String?
    let area: String?
    let address: String?
    let genres: [String]
    let djs: [String]
    let eventType: EventType
    let ageLimit: String?
    let ticketStatus: TicketStatus
    let ticketLink: String?
    let priceTiers: [PriceTier]
    let ticketNote: String?
    let description: String?
    /// True when the promoter is not yet verified by the RaveWatchLagos team.
    /// The feed sends `null` for some events; that is treated as "not flagged".
    let unprovenPromoter: Bool
    let sourceLinks: [String]
    let lastVerified: String?
    let changeLog: [ChangeLogEntry]
    /// Detail flyer image. `flyerImageUrl` in the feed is always null — do
    /// not rely on it; this is the only flyer URL that exists.
    let flyerDetailImageUrl: String?
    /// Base attending count from the feed (anonymous aggregate). Only some
    /// events carry one; the UI adds the user's own local delta on top.
    let attendingCount: Int?
    let followingCount: Int?
    let instagram: InstagramLinks?

    enum CodingKeys: String, CodingKey {
        case id, name, organiser, series, date, endDate, doorsTime
        case venueName, area, address, genres, djs, eventType, ageLimit
        case ticketStatus, ticketLink, priceTiers, ticketNote, description
        case unprovenPromoter, sourceLinks, lastVerified, changeLog
        case flyerDetailImageUrl, flyerImageUrl, attendingCount
        case followingCount, instagram
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        organiser = try container.decodeIfPresent(String.self, forKey: .organiser)
        series = try container.decodeIfPresent(String.self, forKey: .series)
        date = try container.decode(String.self, forKey: .date)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        doorsTime = try container.decodeIfPresent(String.self, forKey: .doorsTime)
        venueName = try container.decodeIfPresent(String.self, forKey: .venueName)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        djs = try container.decodeIfPresent([String].self, forKey: .djs) ?? []
        eventType = try container.decodeIfPresent(EventType.self, forKey: .eventType) ?? .unknown
        ageLimit = try container.decodeIfPresent(String.self, forKey: .ageLimit)
        ticketStatus = try container.decodeIfPresent(TicketStatus.self, forKey: .ticketStatus) ?? .unknown
        ticketLink = try container.decodeIfPresent(String.self, forKey: .ticketLink)
        priceTiers = try container.decodeIfPresent([PriceTier].self, forKey: .priceTiers) ?? []
        ticketNote = try container.decodeIfPresent(String.self, forKey: .ticketNote)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unprovenPromoter = try container.decodeIfPresent(Bool.self, forKey: .unprovenPromoter) ?? false
        sourceLinks = try container.decodeIfPresent([String].self, forKey: .sourceLinks) ?? []
        lastVerified = try container.decodeIfPresent(String.self, forKey: .lastVerified)
        changeLog = try container.decodeIfPresent([ChangeLogEntry].self, forKey: .changeLog) ?? []
        flyerDetailImageUrl = try container.decodeIfPresent(String.self, forKey: .flyerDetailImageUrl)
        attendingCount = try container.decodeIfPresent(Int.self, forKey: .attendingCount)
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        instagram = try container.decodeIfPresent(InstagramLinks.self, forKey: .instagram)
        // flyerImageUrl is intentionally not stored: it is always null.
    }

    // MARK: Dates

    /// Lagos timezone, used for every date shown to the user.
    static let lagosTimeZone = TimeZone(identifier: "Africa/Lagos") ?? TimeZone.current

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses a feed date string, which may be "yyyy-MM-dd" or an ISO-8601
    /// datetime such as "2026-11-28T00:00:00.000".
    static func parseFeedDate(_ string: String) -> Date? {
        if let date = dayFormatter.date(from: string) {
            return date
        }
        if let date = isoWithFractional.date(from: string) {
            return date
        }
        return isoPlain.date(from: string)
    }

    /// The event's start date, or `nil` when the feed string is unparseable.
    var startDate: Date? { Self.parseFeedDate(date) }

    var endDateValue: Date? {
        guard let endDate else { return nil }
        return Self.parseFeedDate(endDate)
    }

    var isMultiDay: Bool {
        guard let start = startDate, let end = endDateValue else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    /// True when the event day has already passed in Lagos.
    var isPast: Bool {
        guard let start = startDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return start < today
    }

    // MARK: Display strings

    private static let sectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = lagosTimeZone
        return formatter
    }()

    private static let longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = lagosTimeZone
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = lagosTimeZone
        return formatter
    }()

    /// Section header, e.g. "Thu 12 Nov".
    var sectionTitle: String {
        guard let start = startDate else { return date }
        return Self.sectionFormatter.string(from: start)
    }

    /// Full date line, e.g. "Thursday, 12 November 2026".
    var displayDate: String {
        guard let start = startDate else { return date }
        var text = Self.longFormatter.string(from: start)
        if let end = endDateValue, isMultiDay {
            text += " – " + Self.shortFormatter.string(from: end)
        }
        return text
    }

    /// "Thu 12 Nov · 8 PM" style line for rows.
    var rowDateLine: String {
        var text = sectionTitle
        if let doorsTime, !doorsTime.isEmpty {
            text += " · \(doorsTime)"
        }
        return text
    }

    /// "Victoria Island · LIVbykuiknosh Restaurant & Grills" style line.
    var placeLine: String? {
        let parts = [area, venueName].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: Prices

    private static let nairaFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_NG")
        formatter.groupingSeparator = ","
        return formatter
    }()

    /// Formats an amount in naira, e.g. 3030 -> "₦3,030".
    static func formatNaira(_ amount: Int) -> String {
        let digits = nairaFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "₦\(digits)"
    }

    var lowestPriceNaira: Int? {
        priceTiers.map(\.priceNaira).min()
    }

    /// True when the cheapest tier is free entry.
    var isFree: Bool {
        lowestPriceNaira == 0
    }

    /// "Free" or "From ₦3,030", or `nil` when no price information exists.
    var priceSummary: String? {
        guard let lowest = lowestPriceNaira else { return nil }
        if lowest == 0 { return "Free" }
        return "From \(Self.formatNaira(lowest))"
    }

    // MARK: URLs

    var flyerURL: URL? {
        guard let raw = flyerDetailImageUrl, let url = URL(string: raw) else { return nil }
        return url
    }

    var ticketURL: URL? {
        guard let raw = ticketLink, let url = URL(string: raw) else { return nil }
        return url
    }

    var mapsURL: URL? {
        let query = [venueName, address, area, "Lagos"].compactMap { $0 }.filter { !$0.isEmpty }
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query.joined(separator: ", "))]
        return components?.url
    }
}

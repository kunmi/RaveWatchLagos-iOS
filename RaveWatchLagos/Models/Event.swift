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
    /// Null = price not published (TBA). 0 = free.
    let priceNaira: Int?
    let note: String?
    /// Non-naira price shown verbatim, e.g. "$19.98" — never converted.
    let priceDisplay: String?

    init(name: String, priceNaira: Int?, note: String? = nil, priceDisplay: String? = nil) {
        self.name = name
        self.priceNaira = priceNaira
        self.note = note
        self.priceDisplay = priceDisplay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        priceNaira = try container.decodeIfPresent(Int.self, forKey: .priceNaira)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        priceDisplay = try container.decodeIfPresent(String.self, forKey: .priceDisplay)
    }

    /// "Free" / "₦3,030" / the verbatim non-naira display / "Price TBA".
    var display: String {
        if let priceNaira {
            if priceNaira == 0 { return "Free" }
            return Event.formatNaira(priceNaira)
        }
        if let priceDisplay, !priceDisplay.isEmpty { return priceDisplay }
        return "Price TBA"
    }
}

// MARK: - Change log

struct ChangeLogEntry: Codable, Identifiable, Hashable {
    var id: String { "\(dateString)-\(description)" }

    /// Raw date string from the feed ("yyyy-MM-dd" or ISO-8601).
    let date: String
    let description: String

    var parsedDate: Date? { Event.parseFeedDate(date) }

    /// "2 Nov 2026", as the detail page's change history shows it.
    var displayDate: String {
        guard let parsedDate else { return date }
        return Event.shortDateFormatter.string(from: parsedDate)
    }
}

// MARK: - Day venue

/// One day's venue for a multi-day event ("Venues by day").
struct DayVenue: Codable, Hashable {
    let date: String
    let venue: String

    var parsedDate: Date? { Event.parseFeedDate(date) }
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

    /// 'club' → "Club Party", anything else → "Rave" (the Flutter label).
    var label: String {
        switch self {
        case .club: return "Club Party"
        case .rave, .unknown: return "Rave"
        }
    }
}

enum TicketStatus: String, Codable {
    case teaser
    case announced
    case ticketsOnSale
    case ticketsSoon
    case soldOut
    case cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = TicketStatus(rawValue: raw) ?? .unknown
    }

    /// Short badge label shown on cards and the detail page.
    var label: String {
        switch self {
        case .teaser: return "Teaser"
        case .announced: return "Announced"
        case .ticketsOnSale: return "Tickets on sale"
        case .ticketsSoon: return "Tickets soon"
        case .soldOut: return "Sold out"
        case .cancelled: return "Cancelled"
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
        case .cancelled: return "Cancelled"
        case .teaser: return "Teaser — no tickets yet"
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
/// Genres are canonicalised to one spelling each at parse, "Rave" /
/// "Club Party" are stripped from genre lists (they are types, not
/// genres), and the type is derived from the genres when the feed omits it
/// — all exactly as the Flutter model's fromJson does.
struct Event: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let organiser: String?
    let series: String?
    /// Raw date string: "yyyy-MM-dd" or an ISO-8601 datetime.
    let date: String
    /// Raw end-date string for multi-day events, same formats as `date`.
    let endDate: String?
    let dayVenues: [DayVenue]
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
    let flyerImageUrl: String?
    /// Base attending count from the feed (anonymous aggregate). Only some
    /// events carry one; the UI overlays live Supabase totals on top.
    let attendingCount: Int?
    let followingCount: Int?
    let instagram: InstagramLinks?

    enum CodingKeys: String, CodingKey {
        case id, name, organiser, series, date, endDate, dayVenues, doorsTime
        case venueName, area, address, genres, djs, eventType, ageLimit
        case ticketStatus, ticketLink, priceTiers, ticketNote, description
        case unprovenPromoter, sourceLinks, lastVerified, changeLog
        case flyerDetailImageUrl, flyerImageUrl, attendingCount
        case followingCount, instagram
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "unknown"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled event"
        organiser = try container.decodeIfPresent(String.self, forKey: .organiser)
        series = try container.decodeIfPresent(String.self, forKey: .series)
        date = try container.decode(String.self, forKey: .date)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        dayVenues = try container.decodeIfPresent([DayVenue].self, forKey: .dayVenues) ?? []
        doorsTime = try container.decodeIfPresent(String.self, forKey: .doorsTime)
        venueName = try container.decodeIfPresent(String.self, forKey: .venueName)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        address = try container.decodeIfPresent(String.self, forKey: .address)

        // Genres: canonicalise, strip type words, dedupe, order preserved.
        let rawGenres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        var cleanGenres: [String] = []
        for raw in rawGenres {
            let canon = Self.canonicalGenre(raw)
            if canon == "Rave" || canon == "Club Party" { continue }
            if !cleanGenres.contains(canon) { cleanGenres.append(canon) }
        }
        genres = cleanGenres

        // DJs: blanks dropped, billing order preserved.
        let rawDJs = try container.decodeIfPresent([String].self, forKey: .djs) ?? []
        djs = rawDJs.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Type: the feed's value when present, derived from genres when absent.
        if let rawType = try container.decodeIfPresent(String.self, forKey: .eventType),
           let parsed = EventType(rawValue: rawType), parsed != .unknown {
            eventType = parsed
        } else {
            eventType = Self.deriveEventType(genres)
        }

        // ageLimit may arrive as a number in the feed — coerce, never crash.
        if let ageString = try? container.decodeIfPresent(String.self, forKey: .ageLimit), let ageString {
            ageLimit = ageString
        } else if let ageInt = try? container.decodeIfPresent(Int.self, forKey: .ageLimit), let ageInt {
            ageLimit = "\(ageInt)"
        } else {
            ageLimit = nil
        }

        ticketStatus = try container.decodeIfPresent(TicketStatus.self, forKey: .ticketStatus) ?? .announced
        ticketLink = try container.decodeIfPresent(String.self, forKey: .ticketLink)
        priceTiers = try container.decodeIfPresent([PriceTier].self, forKey: .priceTiers) ?? []
        ticketNote = try container.decodeIfPresent(String.self, forKey: .ticketNote)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unprovenPromoter = try container.decodeIfPresent(Bool.self, forKey: .unprovenPromoter) ?? false

        // sourceLinks: tolerate a single string as well as a list.
        if let links = try? container.decodeIfPresent([String].self, forKey: .sourceLinks), let links {
            sourceLinks = links
        } else if let single = try? container.decodeIfPresent(String.self, forKey: .sourceLinks), let single {
            sourceLinks = [single]
        } else {
            sourceLinks = []
        }

        lastVerified = try container.decodeIfPresent(String.self, forKey: .lastVerified)

        // Change log, parsed tolerantly: a bad entry is skipped, never a
        // reason to reject the record.
        let rawLog = try container.decodeIfPresent([ChangeLogEntry].self, forKey: .changeLog) ?? []
        changeLog = rawLog.filter { entry in
            entry.parsedDate != nil && !entry.description.trimmingCharacters(in: .whitespaces).isEmpty
        }

        flyerDetailImageUrl = try container.decodeIfPresent(String.self, forKey: .flyerDetailImageUrl)
        flyerImageUrl = try container.decodeIfPresent(String.self, forKey: .flyerImageUrl)
        attendingCount = try container.decodeIfPresent(Int.self, forKey: .attendingCount)
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        instagram = try container.decodeIfPresent(InstagramLinks.self, forKey: .instagram)
    }

    // MARK: Dates

    /// Lagos timezone, used for every date shown to the user.
    static let lagosTimeZone = TimeZone(identifier: "Africa/Lagos") ?? TimeZone.current

    static var lagosCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lagosTimeZone
        return calendar
    }

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

    /// The event's last day (date-only semantics throughout).
    var lastDay: Date {
        guard let start = startDate, let end = endDateValue else { return startDate ?? Date() }
        let calendar = Self.lagosCalendar
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return endDay > startDay ? end : start
    }

    var isMultiDay: Bool {
        guard let start = startDate else { return false }
        return lastDay > Self.lagosCalendar.startOfDay(for: start)
    }

    var totalDays: Int {
        guard let start = startDate else { return 1 }
        let calendar = Self.lagosCalendar
        let days = calendar.dateComponents([.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: lastDay)).day ?? 0
        return days + 1
    }

    /// 1-based day number of `day` within the event, or nil when `day`
    /// is outside the event's span.
    func dayNumberOn(_ day: Date) -> Int? {
        guard let start = startDate else { return nil }
        let calendar = Self.lagosCalendar
        let d = calendar.startOfDay(for: day)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: lastDay)
        if d < startDay || d > endDay { return nil }
        let diff = calendar.dateComponents([.day], from: startDay, to: d).day ?? 0
        return diff + 1
    }

    /// "Day 2 of 3" — shown on cards once a multi-day event is underway
    /// (never on day 1, never before it starts).
    func dayFlag(today: Date = Date()) -> String? {
        guard isMultiDay, let n = dayNumberOn(today), n >= 2 else { return nil }
        return "Day \(n) of \(totalDays)"
    }

    /// True when the event's span touches the window [start, end]
    /// (all date-only) — a multi-day event appears in every window
    /// any of its days falls in.
    func overlaps(start: Date, end: Date) -> Bool {
        guard let eventStart = startDate else { return false }
        let calendar = Self.lagosCalendar
        let s = calendar.startOfDay(for: eventStart)
        let e = calendar.startOfDay(for: lastDay)
        return s <= calendar.startOfDay(for: end) && e >= calendar.startOfDay(for: start)
    }

    /// True when the event day has already passed in Lagos.
    var isPast: Bool {
        guard let start = startDate else { return false }
        let today = Self.lagosCalendar.startOfDay(for: Date())
        return Self.lagosCalendar.startOfDay(for: start) < today
    }

    // MARK: Display strings

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func formatDayLabel(_ date: Date) -> String {
        let calendar = lagosCalendar
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let dayName = dayNames[(weekday + 5) % 7]
        let month = monthNames[calendar.component(.month, from: date) - 1]
        return "\(dayName) \(calendar.component(.day, from: date)) \(month)"
    }

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = lagosTimeZone
        return formatter
    }()

    /// Card/detail date text: "Fri 30 Oct" for a single day, the range
    /// "Fri 30 Oct – Sat 31 Oct" (or "Fri 18 – Sun 20 Dec" within one
    /// month) for a multi-day event.
    var dateLabel: String {
        guard let start = startDate else { return date }
        if !isMultiDay { return Self.formatDayLabel(start) }
        let end = lastDay
        let calendar = Self.lagosCalendar
        if calendar.component(.year, from: start) == calendar.component(.year, from: end)
            && calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            let dayName = dayNames[(calendar.component(.weekday, from: start) + 5) % 7]
            return "\(dayName) \(calendar.component(.day, from: start)) – \(Self.formatDayLabel(end))"
        }
        return "\(Self.formatDayLabel(start)) – \(Self.formatDayLabel(end))"
    }

    /// "Thu 12 Nov".
    var sectionTitle: String {
        guard let start = startDate else { return date }
        return Self.formatDayLabel(start)
    }

    /// Full date line, e.g. "Thursday, 12 November 2026".
    var displayDate: String {
        guard let start = startDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = Self.lagosTimeZone
        var text = formatter.string(from: start)
        if isMultiDay {
            text += " – " + Self.shortDateFormatter.string(from: lastDay)
        }
        return text
    }

    /// "Victoria Island · LIVbykuiknosh Restaurant & Grills" style line.
    var placeLine: String? {
        let parts = [area, venueName].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// "Last verified: 10 Nov 2026" — the feed's lastVerified is a date.
    var lastVerifiedDisplay: String? {
        guard let lastVerified, let parsed = Self.parseFeedDate(lastVerified) else { return lastVerified }
        return Self.shortDateFormatter.string(from: parsed)
    }

    // MARK: Genres / type

    static let raveGenres: Set<String> = ["Techno", "Electronic", "House"]
    static let clubGenres: Set<String> = ["Afrobeats", "Amapiano", "Hip Hop", "R&B"]

    /// Canonical genre spellings, keyed on the name with case, hyphens
    /// and spaces removed. Unknown genres pass through, tidied.
    static let canonicalGenres: [String: String] = [
        "hiphop": "Hip Hop",
        "afrotech": "Afro Tech",
        "afrohouse": "Afro House",
        "deephouse": "Deep House",
        "afrobeats": "Afrobeats",
        "afropiano": "Amapiano",
        "amapiano": "Amapiano",
        "rnb": "R&B",
        "gqom": "Gqom",
        "techno": "Techno",
        "house": "House",
        "electronica": "Electronic",
        "electronic": "Electronic",
        "kompa": "Kompa",
        "3step": "3Step",
    ]

    static func canonicalGenre(_ raw: String) -> String {
        let tidy = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        let key = tidy.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "&" }
        return canonicalGenres[key] ?? tidy
    }

    /// Fallback classification for older feed data without eventType.
    static func deriveEventType(_ genres: [String]) -> EventType {
        genres.contains(where: raveGenres.contains) ? .rave : .club
    }

    /// True when the event genuinely spans both scenes — rave music AND
    /// club music both featured. Such events appear under BOTH Type filters.
    var spansBothScenes: Bool {
        genres.contains(where: Self.raveGenres.contains)
            && genres.contains(where: Self.clubGenres.contains)
    }

    /// Whether this event belongs under a Type filter selection
    /// ("Rave" or "Club Party").
    func matchesType(_ filterLabel: String) -> Bool {
        spansBothScenes || eventType.label == filterLabel
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

    /// Lowest published entry price. Null = no price published yet.
    var entryPriceNaira: Int? {
        priceTiers.compactMap(\.priceNaira).min()
    }

    /// "Free" / "₦3,030" / a verbatim non-naira price / "Price TBA".
    var entryPriceDisplay: String {
        if let price = entryPriceNaira {
            return price == 0 ? "Free" : Self.formatNaira(price)
        }
        for tier in priceTiers {
            if let display = tier.priceDisplay, !display.isEmpty { return display }
        }
        return "Price TBA"
    }

    /// True when the cheapest tier is free entry.
    var isFree: Bool { entryPriceNaira == 0 }

    /// Entry at ₦5,000 or less is a deal.
    var isDeal: Bool {
        isFree || (entryPriceNaira.map { $0 <= 5000 } ?? false)
    }

    /// "Free" or "From ₦3,030", or `nil` when no price information exists.
    var priceSummary: String? {
        guard let lowest = entryPriceNaira else { return nil }
        if lowest == 0 { return "Free" }
        return "From \(Self.formatNaira(lowest))"
    }

    // MARK: New-promoter tag

    /// Whether the card shows the "New promoter" tag: the sweep's
    /// unprovenPromoter flag, suppressed whenever the name or series
    /// carries an edition marker ≥ 2 — a second or later edition is
    /// proof the promoter has run events before, whatever a stale
    /// flag says.
    var showNewPromoterTag: Bool {
        unprovenPromoter
            && !Self.textHasRepeatEditionMarker(name)
            && !Self.textHasRepeatEditionMarker(series)
    }

    /// Edition-marker check, ported from the Flutter model:
    /// "N.0" with N≥2, "Vol N" / "Volume N", "Edition N" / "Nth Edition",
    /// "Part N" / "Pt. N", or a bare integer N≥2 as its own token at the
    /// end of the text or just before a subtitle separator. A 4-digit
    /// year (1900–2099) is a date, never an edition; digits fused into
    /// a larger token ("27k", "10sion") never count.
    static func textHasRepeatEditionMarker(_ text: String?) -> Bool {
        guard let text else { return false }
        let t = text.lowercased()

        func anyAtLeast2(pattern: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(t.startIndex..., in: t)
            for match in regex.matches(in: t, range: range) {
                guard match.numberOfRanges > 1,
                      let groupRange = Range(match.range(at: 1), in: t),
                      let n = Int(t[groupRange]), n >= 2 else { continue }
                return true
            }
            return false
        }

        if anyAtLeast2(pattern: #"(\d+)\.0(?!\d)"#) { return true }
        if anyAtLeast2(pattern: #"\bvol(?:ume)?\.?\s*(\d+)"#) { return true }
        if anyAtLeast2(pattern: #"\bedition\s*(\d+)"#) { return true }
        if anyAtLeast2(pattern: #"(\d+)\s*(?:st|nd|rd|th)\s+edition"#) { return true }
        if anyAtLeast2(pattern: #"\b(?:part|pt)\.?\s*(\d+)"#) { return true }

        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return false }
        let range = NSRange(t.startIndex..., in: t)
        for match in regex.matches(in: t, range: range) {
            guard let tokenRange = Range(match.range, in: t) else { continue }
            let token = String(t[tokenRange])
            let beforeIndex = t.index(tokenRange.lowerBound, offsetBy: -1, limitedBy: t.startIndex)
            let before = beforeIndex.map { String(t[$0]) } ?? ""
            let after = tokenRange.upperBound < t.endIndex ? String(t[tokenRange.upperBound]) : ""
            func fused(_ ch: String) -> Bool {
                guard let first = ch.first else { return false }
                return first.isLetter || first.isNumber
            }
            if fused(before) || fused(after) { continue }
            guard let n = Int(token), n >= 2 else { continue }
            if token.count == 4 && n >= 1900 && n <= 2099 { continue }
            let rest = String(t[tokenRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return true }
            if rest.hasPrefix(":") || rest.hasPrefix("—") || rest.hasPrefix("–") || rest.hasPrefix("- ") {
                return true
            }
        }
        return false
    }

    // MARK: URLs

    /// The image the detail page shows: the detail flyer when captured,
    /// the card flyer as a fallback, else null.
    var detailImageURL: URL? {
        let raw = flyerDetailImageUrl ?? flyerImageUrl
        guard let raw, let url = URL(string: raw) else { return nil }
        return url
    }

    var flyerURL: URL? { detailImageURL }

    var ticketURL: URL? {
        guard let raw = ticketLink, let url = URL(string: raw) else { return nil }
        return url
    }

    /// Google Maps link for the venue — PLACE-FIRST, not straight to
    /// directions: the link opens the venue's Maps place page and lets
    /// the user confirm it's the right place before routing. Null when
    /// there is nothing honestly mappable — venue undisclosed/TBA and
    /// no usable address.
    var directionsURL: URL? {
        guard let parts = placeParts else { return nil }
        let query = (parts + ["Lagos, Nigeria"]).joined(separator: ", ")
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }

    /// The venue as one plain address line — what the ride buttons copy
    /// to the clipboard for pasting as the destination in Bolt or
    /// inDrive, e.g. "B Play Arena, Ajah, Lagos". Null under exactly
    /// the conditions directionsURL is null.
    var rideAddress: String? {
        guard let parts = placeParts else { return nil }
        return (parts + ["Lagos"]).joined(separator: ", ")
    }

    /// The mappable place, as ordered parts: the venue name
    /// (parenthetical asides stripped), the street address when usable,
    /// and the area. Null when there is nothing honestly mappable.
    private var placeParts: [String]? {
        let flags = try? NSRegularExpression(
            pattern: "undisclosed|tba|to be announced|secret location",
            options: .caseInsensitive)
        func unusable(_ value: String?) -> Bool {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
            guard let flags else { return false }
            let range = NSRange(value.startIndex..., in: value)
            return flags.firstMatch(in: value, range: range) != nil
        }

        var venue: String?
        if !unusable(venueName), let rawVenue = venueName {
            let stripped = rawVenue
                .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { venue = stripped }
        }
        let addr = unusable(address) ? nil : address?.trimmingCharacters(in: .whitespaces)

        if let venue {
            return [venue] + (addr.map { [$0] } ?? []) + [area ?? ""].filter { !$0.isEmpty }
        } else if let addr {
            return [addr] + [area ?? ""].filter { !$0.isEmpty }
        }
        return nil
    }
}

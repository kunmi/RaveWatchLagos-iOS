import Foundation

/// Calendar windows for the Feed's calendar sheet, ported from
/// `lib/services/date_window.dart`.
///
/// Presets: all / tonight / tomorrow / thisWeekend / nextWeekend /
/// weekendAfterNext / thisWeek / nextWeek / thisMonth / nextMonth /
/// custom. Weekends are Fri–Sun; weeks are Sun–Sat; months are true
/// calendar periods. "This" windows span the full period (the label
/// names it, e.g. "This week · Oct 25 – Oct 31") though only
/// today-onwards events are listed.
struct DateWindow: Equatable, Hashable {
    let start: Date
    let end: Date
    let label: String

    /// True when the event's span touches this window (overlap, by day).
    func overlaps(event: Event) -> Bool {
        guard let eventStart = event.startDate else { return false }
        let calendar = Event.lagosCalendar
        let s = calendar.startOfDay(for: eventStart)
        let e = calendar.startOfDay(for: event.lastDay)
        return s <= calendar.startOfDay(for: end) && e >= calendar.startOfDay(for: start)
    }
}

enum DateWindowPreset: String, CaseIterable {
    case all
    case tonight
    case tomorrow
    case thisWeekend
    case nextWeekend
    case weekendAfterNext
    case thisWeek
    case nextWeek
    case thisMonth
    case nextMonth
    case custom

    /// Menu label, as the Flutter calendar sheet shows it.
    var menuLabel: String {
        switch self {
        case .all: return "All upcoming"
        case .tonight: return "Tonight"
        case .tomorrow: return "Tomorrow"
        case .thisWeekend: return "This weekend"
        case .nextWeekend: return "Next weekend"
        case .weekendAfterNext: return "Weekend after next"
        case .thisWeek: return "This week"
        case .nextWeek: return "Next week"
        case .thisMonth: return "This month"
        case .nextMonth: return "Next month"
        case .custom: return "Custom dates…"
        }
    }
}

enum DateWindowService {
    /// The window for a preset, relative to `today`. Returns nil for
    /// `all` and `custom` (custom windows come from the range picker).
    static func presetWindow(_ preset: DateWindowPreset, today: Date = Date()) -> DateWindow? {
        let calendar = Event.lagosCalendar
        let t = calendar.startOfDay(for: today)
        func plusDays(_ date: Date, _ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date
        }
        func thisFriday(_ date: Date) -> Date {
            // Dart's _thisFriday: Mon–Fri → Friday of this week;
            // Sat/Sun → the Friday just passed (the weekend in progress).
            let foundationWeekday = calendar.component(.weekday, from: date) // 1 = Sunday
            let dartWeekday = ((foundationWeekday + 5) % 7) + 1 // Mon = 1 … Sun = 7
            if dartWeekday <= 5 {
                return plusDays(date, 5 - dartWeekday)
            }
            return plusDays(date, -(dartWeekday - 5))
        }
        func thisSaturday(_ date: Date) -> Date {
            let weekday = calendar.component(.weekday, from: date)
            let daysToSaturday = (7 - weekday + 7) % 7
            return plusDays(date, daysToSaturday)
        }
        func monthEnd(_ date: Date) -> Date {
            let startOfNextMonth = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: date),
                month: calendar.component(.month, from: date) + 1,
                day: 1)) ?? date
            return plusDays(startOfNextMonth, -1)
        }
        func formatRange(_ start: Date, _ end: Date) -> String {
            "\(Event.formatDayLabel(start)) – \(Event.formatDayLabel(end))"
        }

        switch preset {
        case .all, .custom:
            return nil
        case .tonight:
            return DateWindow(start: t, end: t, label: "Tonight")
        case .tomorrow:
            let day = plusDays(t, 1)
            return DateWindow(start: day, end: day, label: "Tomorrow · \(Event.formatDayLabel(day))")
        case .thisWeekend:
            let fri = thisFriday(t)
            let sun = plusDays(fri, 2)
            return DateWindow(start: fri, end: sun, label: "This weekend · \(formatRange(fri, sun))")
        case .nextWeekend:
            let fri = plusDays(thisFriday(t), 7)
            let sun = plusDays(fri, 2)
            return DateWindow(start: fri, end: sun, label: "Next weekend · \(formatRange(fri, sun))")
        case .weekendAfterNext:
            let fri = plusDays(thisFriday(t), 14)
            let sun = plusDays(fri, 2)
            return DateWindow(start: fri, end: sun, label: "Weekend after next · \(formatRange(fri, sun))")
        case .thisWeek:
            let sat = thisSaturday(t)
            let sun = plusDays(sat, -6)
            return DateWindow(start: sun, end: sat, label: "This week · \(formatRange(sun, sat))")
        case .nextWeek:
            let sun = plusDays(thisSaturday(t), 1)
            let sat = plusDays(sun, 6)
            return DateWindow(start: sun, end: sat, label: "Next week · \(formatRange(sun, sat))")
        case .thisMonth:
            let first = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: t),
                month: calendar.component(.month, from: t),
                day: 1)) ?? t
            let end = monthEnd(t)
            return DateWindow(start: first, end: end, label: "This month · \(formatRange(first, end))")
        case .nextMonth:
            let start = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: t),
                month: calendar.component(.month, from: t) + 1,
                day: 1)) ?? t
            let end = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: t),
                month: calendar.component(.month, from: t) + 2,
                day: 0)) ?? start
            return DateWindow(start: start, end: end, label: "Next month · \(formatRange(start, end))")
        }
    }

    /// A window from the date-range picker.
    static func customWindow(start: Date, end: Date) -> DateWindow {
        let calendar = Event.lagosCalendar
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return DateWindow(start: s, end: e,
                          label: "\(Event.formatDayLabel(s)) – \(Event.formatDayLabel(e))")
    }

    /// 'Sat 7 Nov' — the plain date header (day-first).
    static func formatDayLabel(_ date: Date) -> String {
        Event.formatDayLabel(date)
    }

    /// The Feed section header for an event starting on `date`,
    /// relative to `today`. The signposted zone runs from today through
    /// NEXT weekend: Tonight / Tomorrow / This Weekend / Next Weekend,
    /// with a plain date for any weekday falling between those blocks.
    /// Everything beyond next weekend groups under one catch-all header,
    /// 'Further Out'. Events group by their START date.
    static func feedSectionLabel(date: Date, today: Date = Date()) -> String {
        let calendar = Event.lagosCalendar
        let d = calendar.startOfDay(for: date)
        let t = calendar.startOfDay(for: today)
        if d == t { return "Tonight" }
        if d == calendar.date(byAdding: .day, value: 1, to: t) { return "Tomorrow" }
        if let thisWeekend = presetWindow(.thisWeekend, today: today),
           d >= thisWeekend.start && d <= thisWeekend.end { return "This Weekend" }
        if let nextWeekend = presetWindow(.nextWeekend, today: today) {
            if d >= nextWeekend.start && d <= nextWeekend.end { return "Next Weekend" }
            if d <= nextWeekend.end { return formatDayLabel(d) }
        }
        return "Further Out"
    }
}

import SwiftUI
import UIKit

/// The Feed tab, ported from `lib/screens/feed_screen.dart`.
///
/// - Date-grouped, entry price on every card, area + genre filters,
///   NO price filter (by design), search (name/venue/area/genre/DJ),
///   live attending+following counts overlaid on feed-published counts,
///   "new" markers (violet bar + Just added count) diffed against
///   previously-shown ids, resume refetch if >15 min since last fetch.
/// - Card swipes: right = Follow, left = Attend (0.3 threshold, card
///   springs back, tick/click sounds, destination tab blinks once).
/// - App bar: brand title, theme toggle, refresh (reload + reset
///   filters), settings.
/// - Sections: Tonight / Tomorrow / This Weekend / Next Weekend /
///   plain date / Further Out; no headers while a calendar window is
///   active. Multi-day events group under their start date and match
///   windows by overlap.
/// - Status line: source label (if not Live) • updated label •
///   "new edition daily" if behind • "checking for updates…" if
///   refreshing; freshness dot green/grey.
struct FeedView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var metrics: MetricsService
    @EnvironmentObject private var newEventsStore: NewEventsStore
    @EnvironmentObject private var soundService: SoundService
    @EnvironmentObject private var tourController: TourController
    @EnvironmentObject private var coordinator: TabNavigation

    /// Fired on a completed card swipe (follow or attend), so the shell
    /// can blink the destination tab and advance the tour.
    var onSwipeAction: (FeedSwipeAction) -> Void = { _ in }

    enum FeedSwipeAction { case follow, attend }

    @State private var searchText = ""
    @State private var selectedType: EventTypeFilter = .all
    @State private var areaSel: Set<String> = []
    @State private var genreSel: Set<String> = []
    @State private var window: DateWindow?
    @State private var newOnly = false
    @State private var showAreaSheet = false
    @State private var showGenreSheet = false
    @State private var showCalendarSheet = false
    @State private var showCustomPicker = false

    enum EventTypeFilter: String, CaseIterable {
        case all = "All types"
        case rave = "Rave"
        case club = "Club Party"
    }

    // MARK: - Filtering

    private var filteredEvents: [Event] {
        let events = eventStore.upcomingEvents.filter(passesFilters)
        return events.sorted { lhs, rhs in
            switch (lhs.startDate, rhs.startDate) {
            case let (a?, b?): return a != b ? a < b : lhs.name < rhs.name
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
    }

    private func passesFilters(_ event: Event) -> Bool {
        passesFilters(event, areaSel: areaSel, genreSel: genreSel)
    }

    private func passesFilters(_ event: Event, areaSel: Set<String>, genreSel: Set<String>) -> Bool {
        // Multi-select: an event matches if it sits in ANY picked area /
        // carries ANY picked genre (union per group).
        if !areaSel.isEmpty && !(event.area.map { areaSel.contains($0) } ?? false) { return false }
        if !genreSel.isEmpty && !event.genres.contains(where: genreSel.contains) { return false }
        // Mixed events (both scenes in their genres) match either type.
        if selectedType != .all && !event.matchesType(selectedType.rawValue) { return false }
        // Multi-day events match a window by OVERLAP: any day of the
        // event inside the window is enough.
        if let window, !window.overlaps(event: event) { return false }
        // The Just added pill: only the latest edition's adds —
        // opening one keeps it listed.
        if newOnly && !newEventsStore.isJustAdded(event.id) { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            // Note: the Flutter feed filter matches name/organiser/
            // series/venue/area/genres — it does NOT match DJs. This
            // port also matches DJs, as the brief's search spec asks
            // for (and as v1 did); see README.
            let haystack = [
                event.name,
                event.organiser ?? "",
                event.series ?? "",
                event.venueName ?? "",
                event.area ?? "",
                event.genres.joined(separator: " "),
                event.djs.joined(separator: " "),
            ].joined(separator: " ").lowercased()
            if !haystack.contains(query) { return false }
        }
        return true
    }

    /// Adds count for the pill's label: upcoming events the latest
    /// edition brought — opening them does not move this number.
    private var newCount: Int {
        eventStore.upcomingEvents.filter { newEventsStore.isJustAdded($0.id) }.count
    }

    private var filtersActive: Bool {
        selectedType != .all || !areaSel.isEmpty || !genreSel.isEmpty
            || window != nil || newOnly || !searchText.isEmpty
    }

    // MARK: - Sections

    private struct SectionHeader: Hashable {
        let label: String
        let range: String?
    }

    private var sectioned: [(header: SectionHeader?, events: [Event])] {
        let events = filteredEvents
        // While a calendar window is active there are NO headers — the
        // window chip already names the period.
        guard window == nil else {
            return [(header: nil, events: events)]
        }
        var result: [(header: SectionHeader?, events: [Event])] = []
        var index = 0
        while index < events.count {
            guard let start = events[index].startDate else { index += 1; continue }
            let label = DateWindowService.feedSectionLabel(date: start)
            var end = index
            while end + 1 < events.count,
                  let nextStart = events[end + 1].startDate,
                  DateWindowService.feedSectionLabel(date: nextStart) == label {
                end += 1
            }
            var range: String?
            if (label == "This Weekend" || label == "Next Weekend"),
               let firstStart = events[index].startDate,
               let lastStart = events[end].startDate,
               !Calendar.current.isDate(firstStart, inSameDayAs: lastStart) {
                range = "\(Event.formatDayLabel(firstStart)) – \(Event.formatDayLabel(lastStart))"
            }
            result.append((header: SectionHeader(label: label, range: range),
                           events: Array(events[index...end])))
            index = end + 1
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $coordinator.feedPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        searchField
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        filterBar
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .tourAnchor(.feedFilters)

                        chipsRow
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        statusLine
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if eventStore.events.isEmpty && !eventStore.isLoading {
                            ContentUnavailableView(
                                "No events right now",
                                systemImage: "moon.stars",
                                description: Text("Pull to refresh to try the live feed again.")
                            )
                            .padding(.top, 40)
                        } else if filteredEvents.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        } else {
                            ForEach(sectioned, id: \.header) { section in
                                if let header = section.header {
                                    sectionHeaderView(header)
                                }
                                ForEach(section.events) { event in
                                    FeedCardSwipe(
                                        onFollow: { swipeFollow(event) },
                                        onAttend: { swipeAttend(event) }
                                    ) {
                                        EventCardView(
                                            event: event,
                                            attendingCount: eventStore.attendingCount(for: event),
                                            followingCount: eventStore.followingCount(for: event),
                                            isNew: newEventsStore.isNew(event.id),
                                            onShare: { shareEvent(event) },
                                            onTap: { openEvent(event) }
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .id(event.id)
                                        .if(event.id == filteredEvents.first?.id) { view in
                                            view.tourAnchor(.feedCard)
                                        }
                                    }
                                }
                            }
                        }

                        Text("\(filteredEvents.count) event\(filteredEvents.count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
                .refreshable {
                    // Pull-to-refresh is reload-only (it does not reset
                    // the filters — that is the app-bar button's job).
                    await eventStore.refresh()
                    await eventStore.syncCounts()
                }
                .onChange(of: tourController.feedScrollTopTick) { _, _ in
                    if let first = filteredEvents.first {
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandTitle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { userStore.toggleTheme() } label: {
                        Image(systemName: themeToggleIcon)
                    }
                    .tourAnchor(.feedTheme)
                    .accessibilityLabel("Toggle theme")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetFilters()
                        Task {
                            await eventStore.refresh()
                            await eventStore.syncCounts()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload and reset filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coordinator.feedPath.append(Route.settings) } label: {
                        Image(systemName: "gearshape")
                    }
                    .tourAnchor(.feedSettings)
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                routeDestination(route)
            }
        }
        .sheet(isPresented: $showAreaSheet) {
            MultiSelectSheet(
                title: "Area",
                options: eventStore.allAreas.dropFirst(),
                selected: $areaSel,
                facetedCounts: facetedAreaCounts,
                countForSelection: { draft in
                    eventStore.upcomingEvents.filter {
                        passesFilters($0, areaSel: draft, genreSel: genreSel)
                    }.count
                },
                onClear: { areaSel.removeAll() }
            )
        }
        .sheet(isPresented: $showGenreSheet) {
            MultiSelectSheet(
                title: "Genre",
                options: eventStore.allGenres.dropFirst(),
                selected: $genreSel,
                facetedCounts: facetedGenreCounts,
                countForSelection: { draft in
                    eventStore.upcomingEvents.filter {
                        passesFilters($0, areaSel: areaSel, genreSel: draft)
                    }.count
                },
                onClear: { genreSel.removeAll() }
            )
        }
        .sheet(isPresented: $showCalendarSheet) {
            CalendarSheet(window: $window, isPresented: $showCalendarSheet,
                          showCustomPicker: $showCustomPicker)
        }
        .sheet(isPresented: $showCustomPicker) {
            CustomDateRangeSheet(window: $window, isPresented: $showCustomPicker)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .event(let event):
            EventDetailView(event: event)
        case .eventReadOnly(let event):
            EventDetailView(event: event, readOnly: true)
        case .settings:
            SettingsView()
        }
    }

    private var themeToggleIcon: String {
        switch userStore.theme {
        case .night: return "sun.max"
        case .light: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    // MARK: - Filter bar

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search events, organisers, venues…", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Type dropdown (All types / Rave / Club Party).
                Menu {
                    ForEach(EventTypeFilter.allCases, id: \.self) { type in
                        Button(type.rawValue) { selectedType = type }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedType.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .tourAnchor(.feedTypeRow)

                // Just added pill (bolt icon, violet, edition-pinned count).
                if newCount > 0 {
                    Button {
                        newOnly.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text(newOnly ? "Just added · \(newCount)" : "Just added")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(newOnly ? Color.newViolet : Color.newViolet.opacity(0.15))
                        .foregroundStyle(newOnly ? .white : Color.newViolet)
                        .clipShape(Capsule())
                    }
                }

                Spacer()

                // Calendar button.
                Button { showCalendarSheet = true } label: {
                    CalendarIconView(active: window != nil, size: 24)
                }
                .accessibilityLabel("Calendar")
            }

            HStack(spacing: 8) {
                filterMenuButton(title: "Area", count: areaSel.count) {
                    showAreaSheet = true
                }
                filterMenuButton(title: "Genre", count: genreSel.count) {
                    showGenreSheet = true
                }
                if filtersActive {
                    Button("Clear all", role: .destructive) {
                        resetFilters()
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
        }
    }

    private func filterMenuButton(title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(count > 0 ? "\(title) · \(count)" : title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private var chipsRow: some View {
        // Picked areas/genres as removable chips, plus the window chip.
        let chips = areaSel.sorted() + genreSel.sorted()
        return Group {
            if !chips.isEmpty || window != nil {
                ChipFlow(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            areaSel.remove(chip)
                            genreSel.remove(chip)
                        } label: {
                            HStack(spacing: 4) {
                                Text(chip)
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    if let window {
                        Button { self.window = nil } label: {
                            HStack(spacing: 4) {
                                Text(window.label)
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(eventStore.freshness == .latest ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(eventStore.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeaderView(_ header: SectionHeader) -> some View {
        HStack(spacing: 10) {
            Text(header.label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .tracking(1.1)
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(height: 1)
            if let range = header.range {
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        Group {
            if newOnly {
                Text("You're all caught up. New events from the nightly update will show up here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No events match \"\(searchText.trimmingCharacters(in: .whitespaces))\".")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            } else {
                Text("No events for that filter yet.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func resetFilters() {
        selectedType = .all
        areaSel.removeAll()
        genreSel.removeAll()
        window = nil
        newOnly = false
        searchText = ""
    }

    // MARK: - Faceted counts

    /// Counts per area option among events passing every filter EXCEPT
    /// the area filter.
    private var facetedAreaCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for event in eventStore.upcomingEvents {
            guard passesFiltersIgnoringArea(event), let area = event.area else { continue }
            counts[area, default: 0] += 1
        }
        return counts
    }

    private var facetedGenreCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for event in eventStore.upcomingEvents {
            guard passesFiltersIgnoringGenre(event) else { continue }
            for genre in event.genres {
                counts[genre, default: 0] += 1
            }
        }
        return counts
    }

    private func passesFiltersIgnoringArea(_ event: Event) -> Bool {
        if !genreSel.isEmpty && !event.genres.contains(where: genreSel.contains) { return false }
        if selectedType != .all && !event.matchesType(selectedType.rawValue) { return false }
        if let window, !window.overlaps(event: event) { return false }
        if newOnly && !newEventsStore.isJustAdded(event.id) { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            let haystack = [event.name, event.organiser ?? "", event.series ?? "",
                            event.venueName ?? "", event.area ?? "",
                            event.genres.joined(separator: " "),
                            event.djs.joined(separator: " ")].joined(separator: " ").lowercased()
            if !haystack.contains(query) { return false }
        }
        return true
    }

    private func passesFiltersIgnoringGenre(_ event: Event) -> Bool {
        if !areaSel.isEmpty && !(event.area.map { areaSel.contains($0) } ?? false) { return false }
        if selectedType != .all && !event.matchesType(selectedType.rawValue) { return false }
        if let window, !window.overlaps(event: event) { return false }
        if newOnly && !newEventsStore.isJustAdded(event.id) { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            let haystack = [event.name, event.organiser ?? "", event.series ?? "",
                            event.venueName ?? "", event.area ?? "",
                            event.genres.joined(separator: " "),
                            event.djs.joined(separator: " ")].joined(separator: " ").lowercased()
            if !haystack.contains(query) { return false }
        }
        return true
    }

    // MARK: - Actions

    private func openEvent(_ event: Event) {
        newEventsStore.markRead(event.id)
        coordinator.feedPath.append(Route.event(event))
    }

    private func shareEvent(_ event: Event) {
        metrics.recordShare(event.id)
        ShareService.presentShareSheet(ShareService.shareText(for: event))
    }

    private func swipeFollow(_ event: Event) {
        // The gesture itself always counts for the sound and the tour;
        // the follow only applies when it changes something.
        soundService.playTick()
        onSwipeAction(.follow)
        guard !userStore.isFollowing(event) else { return }
        metrics.recordFollow(event.id)
        userStore.toggleFollow(event)
        Task {
            await eventStore.bumpFollowing(event: event, delta: 1)
        }
    }

    private func swipeAttend(_ event: Event) {
        soundService.playClick()
        onSwipeAction(.attend)
        guard !userStore.isAttending(event) else { return }
        userStore.setAttending(event, going: true)
        Task {
            await eventStore.bumpAttending(event: event, delta: 1)
        }
    }
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Multi-select filter sheet

/// Area / Genre multi-select sheet: checkboxes, faceted counts per
/// option, a "Show N events" button, Clear all.
struct MultiSelectSheet: View {
    let title: String
    let options: ArraySlice<String>
    @Binding var selected: Set<String>
    let facetedCounts: [String: Int]
    /// Events the draft selection would show — the "Show N events" label.
    let countForSelection: (Set<String>) -> Int
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(options), id: \.self) { option in
                    Button {
                        if draft.contains(option) {
                            draft.remove(option)
                        } else {
                            draft.insert(option)
                        }
                    } label: {
                        HStack {
                            Image(systemName: draft.contains(option) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(draft.contains(option) ? Color.accentColor : .secondary)
                            Text(option)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(facetedCounts[option] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear all") {
                        draft.removeAll()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show \(countForSelection(draft)) event\(countForSelection(draft) == 1 ? "" : "s")") {
                        selected = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = selected }
        }
    }
}

// MARK: - Calendar sheet

/// The Feed's calendar sheet: All upcoming, Tonight, Tomorrow, the
/// three weekends, This/Next week, This/Next month, Custom dates…
struct CalendarSheet: View {
    @Binding var window: DateWindow?
    @Binding var isPresented: Bool
    @Binding var showCustomPicker: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(presetRows, id: \.preset) { row in
                    Button {
                        window = row.window
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: row.icon)
                                .frame(width: 24)
                            Text(row.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isCurrent(row) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                Button {
                    isPresented = false
                    showCustomPicker = true
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                            .frame(width: 24)
                        Text("Custom dates…")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("When")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private struct PresetRow {
        let preset: DateWindowPreset
        let icon: String
        let label: String
        let window: DateWindow?
    }

    private var presetRows: [PresetRow] {
        let today = Date()
        func row(_ preset: DateWindowPreset, icon: String) -> PresetRow {
            let window = DateWindowService.presetWindow(preset, today: today)
            return PresetRow(preset: preset, icon: icon,
                             label: preset.menuLabel, window: window)
        }
        return [
            PresetRow(preset: .all, icon: "calendar", label: "All upcoming", window: nil),
            row(.tonight, icon: "moon.stars"),
            row(.tomorrow, icon: "sun.max"),
            row(.thisWeekend, icon: "party.popper"),
            row(.nextWeekend, icon: "calendar.badge.clock"),
            row(.weekendAfterNext, icon: "calendar.badge.clock"),
            row(.thisWeek, icon: "calendar"),
            row(.nextWeek, icon: "calendar"),
            row(.thisMonth, icon: "calendar"),
            row(.nextMonth, icon: "calendar"),
        ]
    }

    private func isCurrent(_ row: PresetRow) -> Bool {
        if row.preset == .all { return window == nil }
        return window == row.window
    }
}

/// Custom date range picker: first date today, last date +150 days.
struct CustomDateRangeSheet: View {
    @Binding var window: DateWindow?
    @Binding var isPresented: Bool

    @State private var startDate = Date()
    @State private var endDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $startDate, in: Date()...maxDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate...maxDate, displayedComponents: .date)
            }
            .navigationTitle("Custom dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        window = DateWindowService.customWindow(start: startDate, end: endDate)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? startDate
            }
        }
    }

    private var maxDate: Date {
        Calendar.current.date(byAdding: .day, value: 150, to: Date()) ?? Date()
    }
}

// MARK: - Calendar icon

/// The Feed's calendar icon — a drawn calendar page, not the stock
/// glyph, with separate fits for the two themes: on the night theme
/// the page is a light outline with the brand-violet header band; on
/// the light theme the page is a dark outline over white, same violet
/// band. When a date window is active the page fills in, so the state
/// reads at a glance in both themes.
struct CalendarIconView: View {
    let active: Bool
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let dark = colorScheme == .dark
            let ink = dark ? Color(red: 0xF1 / 255, green: 0xF0 / 255, blue: 0xFF / 255)
                           : Color(red: 0x23 / 255, green: 0x20 / 255, blue: 0x38 / 255)
            let paper = dark ? Color(red: 0x1C / 255, green: 0x1A / 255, blue: 0x29 / 255) : .white
            let violet = Color.newViolet

            let pageRect = CGRect(x: w * 0.08, y: h * 0.14, width: w * 0.84, height: h * 0.78)
            let pagePath = Path(roundedRect: pageRect, cornerRadius: w * 0.12)
            context.fill(pagePath, with: .color(active ? violet : paper))
            context.stroke(pagePath, with: .color(active ? violet : ink), lineWidth: w * 0.055)

            // Header band.
            let bandHeight = h * 0.22
            var bandPath = Path()
            bandPath.addRoundedRect(in: CGRect(x: w * 0.08, y: h * 0.14, width: w * 0.84, height: bandHeight + w * 0.12),
                                    cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
            // Clip the band to the page so its bottom corners don't poke out.
            let clipPath = Path(roundedRect: pageRect, cornerRadius: w * 0.12)
            context.saveGState()
            context.clip(to: clipPath)
            context.fill(bandPath, with: .color(active ? ink : violet))
            context.restoreGState()

            // Binder rings.
            for x in [0.30, 0.70] {
                var ring = Path()
                ring.move(to: CGPoint(x: w * x, y: h * 0.06))
                ring.addLine(to: CGPoint(x: w * x, y: h * 0.26))
                context.stroke(ring, with: .color(active ? violet : ink),
                               style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            }

            // Date dots (2 rows x 3).
            let dotColor = active ? Color.white
                : (dark ? Color(red: 0xC9 / 255, green: 0xC4 / 255, blue: 0xE8 / 255)
                        : Color(red: 0x6E / 255, green: 0x68 / 255, blue: 0x90 / 255))
            for y in [0.52, 0.72] {
                for x in [0.30, 0.50, 0.70] {
                    let dot = Path(ellipseIn: CGRect(x: w * x - w * 0.055, y: h * y - w * 0.055,
                                                     width: w * 0.11, height: w * 0.11))
                    context.fill(dot, with: .color(dotColor))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

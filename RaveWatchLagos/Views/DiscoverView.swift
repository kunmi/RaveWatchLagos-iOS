import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var userStore: UserStore

    @State private var searchText = ""
    @State private var selectedType: EventTypeFilter = .all
    @State private var selectedGenre: String?
    @State private var selectedArea: String?
    @State private var freeOnly = false
    @State private var ticketsOnSaleOnly = false
    @State private var showPast = false

    enum EventTypeFilter: String, CaseIterable {
        case all = "All"
        case rave = "Rave"
        case club = "Club"
    }

    // MARK: - Filtering

    private var filteredEvents: [Event] {
        eventStore.events.filter { event in
            if !showPast && event.isPast { return false }
            switch selectedType {
            case .all: break
            case .rave: guard event.eventType == .rave else { return false }
            case .club: guard event.eventType == .club else { return false }
            }
            if let genre = selectedGenre, !event.genres.contains(genre) { return false }
            if let area = selectedArea, event.area != area { return false }
            if freeOnly && !event.isFree { return false }
            if ticketsOnSaleOnly && event.ticketStatus != .ticketsOnSale { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let haystack = [
                    event.name,
                    event.organiser,
                    event.series,
                    event.venueName,
                    event.area,
                    event.address,
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                    + " " + event.genres.joined(separator: " ").lowercased()
                    + " " + event.djs.joined(separator: " ").lowercased()
                guard haystack.contains(query) else { return false }
            }
            return true
        }
    }

    private var groupedEvents: [(day: Date, events: [Event])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.startDate ?? .distantFuture)
        }
        return grouped.keys.sorted().map { day in
            (day: day, events: grouped[day] ?? [])
        }
    }

    private var filtersActive: Bool {
        selectedType != .all || selectedGenre != nil || selectedArea != nil
            || freeOnly || ticketsOnSaleOnly || !searchText.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                filterSection

                if eventStore.events.isEmpty && !eventStore.isLoading {
                    ContentUnavailableView(
                        "No events right now",
                        systemImage: "moon.stars",
                        description: Text("Pull to refresh to try the live feed again.")
                    )
                } else if groupedEvents.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try clearing a filter or searching for something else.")
                    )
                } else {
                    ForEach(groupedEvents, id: \.day) { group in
                        Section(header: Text(sectionTitle(for: group.day))) {
                            ForEach(group.events) { event in
                                NavigationLink(value: event) {
                                    EventRow(event: event)
                                }
                            }
                        }
                    }
                }

                footerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("RaveWatchLagos")
            .searchable(text: $searchText, prompt: "Search events, DJs, venues…")
            .refreshable {
                await eventStore.refresh()
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .toolbar {
                if eventStore.isLoading {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Sections

    private var filterSection: some View {
        Section {
            Picker("Type", selection: $selectedType) {
                ForEach(EventTypeFilter.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Button("All genres") { selectedGenre = nil }
                ForEach(eventStore.allGenres, id: \.self) { genre in
                    Button(genre) { selectedGenre = genre }
                }
            } label: {
                filterRowLabel(title: "Genre", value: selectedGenre ?? "All")
            }

            Menu {
                Button("All areas") { selectedArea = nil }
                ForEach(eventStore.allAreas, id: \.self) { area in
                    Button(area) { selectedArea = area }
                }
            } label: {
                filterRowLabel(title: "Area", value: selectedArea ?? "All")
            }

            Toggle("Free entry only", isOn: $freeOnly)
            Toggle("Tickets on sale only", isOn: $ticketsOnSaleOnly)
            Toggle("Show past events", isOn: $showPast)

            if filtersActive {
                Button("Clear all filters", role: .destructive) {
                    selectedType = .all
                    selectedGenre = nil
                    selectedArea = nil
                    freeOnly = false
                    ticketsOnSaleOnly = false
                    searchText = ""
                }
            }
        } header: {
            Text("Filters")
        }
    }

    private func filterRowLabel(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(filteredEvents.count) event\(filteredEvents.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let updated = eventStore.lastUpdated {
                    Text("Feed updated \(updated, format: .dateTime.day().month().year().hour().minute())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Showing the bundled list from 10 Nov 2026 — pull to refresh for the live feed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = eventStore.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = Locale(identifier: "en_NG")
        formatter.timeZone = Event.lagosTimeZone
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today · " + formatter.string(from: day) }
        if calendar.isDateInTomorrow(day) { return "Tomorrow · " + formatter.string(from: day) }
        return formatter.string(from: day)
    }
}

#Preview {
    DiscoverView()
        .environmentObject(EventStore())
        .environmentObject(UserStore())
}

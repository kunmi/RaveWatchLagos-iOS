import SwiftUI

/// "You" tab: on-device usage summary, theme, data source, privacy and links.
/// Nothing here leaves the phone.
struct ProfileView: View {
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var eventStore: EventStore

    private static let dataRepoURL = URL(string: "https://github.com/fabat01/ravewatchlagos-data")
    private static let instagramURL = URL(string: "https://www.instagram.com/ravewatchlagos")

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your activity — on this device only") {
                    statRow(label: "Events viewed", value: userStore.eventsViewedCount)
                    statRow(label: "Events followed", value: userStore.followedCount)
                    statRow(label: "Going to", value: userStore.attendingYesCount)
                    statRow(label: "Events shared", value: userStore.eventsSharedCount)
                    Text("These counts are stored on your phone only. They are never uploaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $userStore.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Night is the default — this is a nightlife app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    if let url = Self.dataRepoURL {
                        Link("Event data: fabat01/ravewatchlagos-data on GitHub",
                             destination: url)
                    }
                    if let updated = eventStore.lastUpdated {
                        Text("Feed last updated \(updated, format: .dateTime.day().month().year().hour().minute())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(eventStore.events.count) events in the current feed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                    if let url = Self.instagramURL {
                        Link("Instagram @ravewatchlagos",
                             destination: url)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Text("RaveWatchLagos lists raves and DJ-led nightlife in Lagos, Nigeria. For adults — many events are 18+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("You")
        }
    }

    private func statRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(UserStore())
        .environmentObject(EventStore())
}

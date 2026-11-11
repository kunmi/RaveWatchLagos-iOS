import SwiftUI
import UIKit

/// Settings, ported from `lib/screens/settings_screen.dart`.
///
/// The screen exists for the public product — Appearance + About today.
/// There is deliberately NO Notifications section: push notifications
/// are still undecided (the Android team is weighing whether they bring
/// any usefulness at all), and a settings section for an unbuilt,
/// undecided feature would be decoration. If push is ever decided, its
/// switches land here.
///
/// iOS differences from the Flutter screen (see README): the theme is
/// a three-way Night / Light / System choice (Flutter toggles night/
/// light only — System is the iOS-appropriate addition), and the bug
/// report's diagnostics say iPhone / iOS version instead of the
/// Android phone / Android version.
struct SettingsView: View {
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var soundService: SoundService
    @EnvironmentObject private var tourStore: TourStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Picker("Theme", selection: $userStore.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Text("Night is the default — this is a nightlife app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(isOn: $soundService.soundsOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Swipe sounds")
                        Text(soundService.soundsOn ? "Swipe sounds are on" : "Swipe sounds are off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sounds")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(VersionLabel.current)
                        .foregroundStyle(.secondary)
                }

                Button {
                    // The app shell hears this, pops back to the shell
                    // itself and restarts the tour — popping here as
                    // well would pop the shell's own route right from
                    // under the tour.
                    tourStore.requestReplay()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replay the tutorial")
                                .foregroundStyle(.primary)
                            Text("The first-launch tour, again")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    openMailto(BugReport.feedbackMailto(),
                               fallback: "Could not open your mail app — write to us at ravewatchlagos@gmail.com")
                } label: {
                    HStack {
                        Text("Send feedback")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    // A separate door from Send feedback, because a bug
                    // report needs facts, not impressions — the composed
                    // email carries the app version, phone and iOS
                    // version plus prompts. If gathering the details
                    // fails, the report still opens, marked "unknown".
                    let diagnostics = BugReport.gatherDiagnostics()
                    openMailto(BugReport.bugReportMailto(diagnostics),
                               fallback: "Could not open your mail app — report the bug to ravewatchlagos@gmail.com")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Report a bug")
                                .foregroundStyle(.primary)
                            Text("App version and phone details included automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink(value: Route.privacy) {
                    Text("Privacy policy")
                }
            } header: {
                Text("About")
            }

            Text("Listings updated daily from public sources.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Opens an external link. If it fails, SAY so and spell out the
    /// destination instead of swallowing the tap.
    private func openMailto(_ url: URL?, fallback: String) {
        guard let url else {
            toastCenter.show(fallback, duration: 4)
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                toastCenter.show(fallback, duration: 4)
            }
        }
    }
}

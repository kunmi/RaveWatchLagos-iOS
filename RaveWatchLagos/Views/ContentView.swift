import SwiftUI

/// Navigation routes, shared by the three tabs' stacks.
enum Route: Hashable {
    case event(Event)
    /// A read-only detail page (tour demo cards) — no stores, so the
    /// example event can be looked at but not followed or counted.
    case eventReadOnly(Event)
    case settings
    case privacy
}

/// The three tabs' navigation paths, owned by the shell so a Settings
/// "Replay the tutorial" can pop every pushed screen before the tour
/// restarts.
@MainActor
final class TabNavigation: ObservableObject {
    @Published var feedPath = NavigationPath()
    @Published var followingPath = NavigationPath()
    @Published var attendingPath = NavigationPath()

    func popAll() {
        feedPath = NavigationPath()
        followingPath = NavigationPath()
        attendingPath = NavigationPath()
    }
}

/// The app shell, ported from `lib/main.dart`.
///
/// Bottom bar: Following · Feed (home) · Attending — home sits in the
/// middle, matching the card swipes (right = Follow to the left tab,
/// left = Attend to the right tab). The app opens on Home.
///
/// After a feed-card swipe, the destination the event went to flashes
/// once IN THE ACTION'S COLOUR — purple for Follow, green for Attend —
/// so the user sees what was registered and where it landed.
struct ContentView: View {
    @EnvironmentObject private var tourStore: TourStore
    @EnvironmentObject private var tourController: TourController
    @EnvironmentObject private var coordinator: TabNavigation
    @EnvironmentObject private var toastCenter: ToastCenter

    /// Bottom-bar index: 0 Following · 1 Feed · 2 Attending.
    @State private var selectedTab = 1
    /// Which bottom-bar destination blinks after a card swipe, and a
    /// serial that re-triggers the blink on repeat swipes to the same
    /// destination.
    @State private var followingPulse = 0
    @State private var attendingPulse = 0
    /// The tour anchors' on-screen frames, published up from the tabs.
    @State private var anchorFrames: [TourAnchor: CGRect] = [:]
    @State private var lastReplayTick = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case 0:
                        FollowingView(
                            onTourCardAction: { tourController.actionDone(.followingSwipe) }
                        )
                    case 2:
                        AttendingView(
                            onTourCardAction: { tourController.actionDone(.attendingSwipe) },
                            onTourShareAction: { tourController.actionDone(.sharePicks) }
                        )
                    default:
                        FeedView(
                            onSwipeAction: { action in
                                switch action {
                                case .follow: followingPulse += 1
                                case .attend: attendingPulse += 1
                                }
                                tourController.actionDone(.feedSwipe)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AppNavBar(
                    selectedTab: $selectedTab,
                    followingPulse: followingPulse,
                    attendingPulse: attendingPulse
                )
            }

            // Snackbar, above the tab bar.
            if let toast = toastCenter.current {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(toast.message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        if let label = toast.actionLabel {
                            Button(label) {
                                toast.action?()
                                toastCenter.dismiss()
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.newViolet)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 0x32 / 255, green: 0x32 / 255, blue: 0x32 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if tourController.active {
                TourOverlay(controller: tourController, frames: anchorFrames) {
                    endTour()
                }
            }
        }
        .onPreferenceChange(TourAnchorPreferenceKey.self) { frames in
            anchorFrames = frames
        }
        .onChange(of: tourController.stepIndex) { _, _ in
            selectedTab = tourController.step.tab
        }
        .onChange(of: tourController.active) { wasActive, isActive in
            // The tour ended (Done, or the last action step advanced
            // past the final step): mark it seen and land on the Feed.
            if wasActive && !isActive {
                tourStore.markSeen()
                selectedTab = 1
            }
        }
        .onChange(of: tourStore.replayTick) { _, tick in
            guard tick != lastReplayTick else { return }
            lastReplayTick = tick
            // Settings → "Replay the tutorial": pop any pushed screen
            // (Settings itself) and restart the tour from step one,
            // on the Feed.
            coordinator.popAll()
            selectedTab = 1
            tourController.start()
        }
        .onAppear {
            lastReplayTick = tourStore.replayTick
        }
    }

    private func endTour() {
        tourStore.markSeen()
        tourController.end()
        selectedTab = 1
    }
}

// MARK: - Bottom bar

/// The app's bottom bar. It looks like the Material 3 NavigationBar it
/// replaces — same 80pt height, same bar colour, same selection pill,
/// same label style — but it is built from plain views because the
/// native tab bar cannot colour ONE destination's label: after a card
/// swipe, the destination's icon AND label blink once in the action's
/// colour, as the bar's own label, recoloured in place.
struct AppNavBar: View {
    @Binding var selectedTab: Int
    let followingPulse: Int
    let attendingPulse: Int

    var body: some View {
        HStack(spacing: 0) {
            NavTile(
                icon: "bell", label: "Following",
                selected: selectedTab == 0,
                flashColor: .deepPurple, pulse: followingPulse
            ) { selectedTab = 0 }
            NavTile(
                icon: "house", label: "Feed",
                selected: selectedTab == 1,
                flashColor: nil, pulse: 0
            ) { selectedTab = 1 }
            NavTile(
                icon: "calendar.badge.checkmark", label: "Attending",
                selected: selectedTab == 2,
                flashColor: .attendGreen, pulse: attendingPulse
            ) { selectedTab = 2 }
        }
        .frame(height: 80)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

/// One destination of the AppNavBar: the M3 selection pill around the
/// icon, the label under it. Tapping anywhere on the tile selects the
/// destination.
struct NavTile: View {
    let icon: String
    let label: String
    let selected: Bool
    let flashColor: Color?
    let pulse: Int
    let onTap: () -> Void

    /// The blink progress, 0 → 1 across 1000 ms; the colour swings to
    /// the action colour and back as a single sine wave.
    @State private var progress: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.clear)
                        .frame(width: 64, height: 32)
                    Image(systemName: selected ? filledIcon : icon)
                        .font(.system(size: 22))
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onChange(of: pulse) { _, newPulse in
            guard newPulse > 0 else { return }
            progress = 0
            withAnimation(.linear(duration: 1)) {
                progress = 1
            }
        }
    }

    private var filledIcon: String {
        switch icon {
        case "bell": return "bell.fill"
        case "house": return "house.fill"
        default: return icon
        }
    }

    /// One wave: 0 → 1 → 0 across the run. At rest the colour is
    /// EXACTLY the resting colour, not a lerp hair off it.
    private var wave: CGFloat {
        (progress == 0 || progress == 1) ? 0 : sin(.pi * progress)
    }

    private func blinked(base: Color, flash: Color?) -> Color {
        guard let flash, wave > 0 else { return base }
        return base.blended(with: flash, fraction: wave)
    }

    private var iconColor: Color {
        let base: Color = selected ? Color.accentColor : Color.secondary
        return blinked(base: base, flash: flashColor)
    }

    private var labelColor: Color {
        let base: Color = selected ? Color.primary : Color.secondary
        return blinked(base: base, flash: flashColor)
    }
}

extension Color {
    /// Linear interpolation between two colours (for the tab blink).
    /// Components are read from the CG colour, handling both RGB and
    /// grayscale system colours.
    func blended(with other: Color, fraction: CGFloat) -> Color {
        func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            guard let comps = UIColor(color).cgColor.components else { return (0, 0, 0, 1) }
            if comps.count >= 4 { return (comps[0], comps[1], comps[2], comps[3]) }
            if comps.count == 2 { return (comps[0], comps[0], comps[0], comps[1]) }
            return (0, 0, 0, 1)
        }
        let from = rgba(self)
        let to = rgba(other)
        let t = min(1, max(0, fraction))
        return Color(red: from.r + (to.r - from.r) * t,
                     green: from.g + (to.g - from.g) * t,
                     blue: from.b + (to.b - from.b) * t,
                     opacity: from.a + (to.a - from.a) * t)
    }
}

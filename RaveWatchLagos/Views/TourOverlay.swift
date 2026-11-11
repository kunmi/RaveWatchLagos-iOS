import SwiftUI

// MARK: - Anchor publishing

/// Preference key carrying the on-screen (window-coordinate) frames of
/// the tour's anchor views, published up to the shell.
struct TourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [TourAnchor: CGRect] = [:]
    static func reduce(value: inout [TourAnchor: CGRect], nextValue: () -> [TourAnchor: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's global frame under `anchor` so the tour
    /// overlay can cut its spotlight hole around it.
    func tourAnchor(_ anchor: TourAnchor) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TourAnchorPreferenceKey.self,
                                value: [anchor: proxy.frame(in: .global)])
            }
        )
    }
}

// MARK: - Tour controller

/// The tour's live state, owned by the shell: whether it is running,
/// which step it is on, and the scroll ticks the tabs listen for.
/// (Persistence — seen flag, replay requests — lives in TourStore.)
@MainActor
final class TourController: ObservableObject {
    @Published var active = false
    @Published var stepIndex = 0
    /// Increments when the tour wants the Feed scrolled to the top
    /// (card steps inherit wherever the user left the feed scrolled).
    @Published var feedScrollTopTick = 0
    /// Increments when the tour wants the Following list scrolled to
    /// the top (card steps) or the bottom (the alert-inbox step).
    @Published var followingScrollTick = 0
    @Published var followingScrollToBottom = false

    var step: TourStep { TourStep.all[stepIndex] }
    var isFirst: Bool { stepIndex == 0 }
    var isLast: Bool { stepIndex == TourStep.all.count - 1 }

    func start() {
        stepIndex = 0
        active = true
    }

    func end() {
        active = false
    }

    func next() {
        if isLast {
            end()
        } else {
            goTo(stepIndex + 1)
        }
    }

    func back() {
        guard stepIndex > 0 else { return }
        goTo(stepIndex - 1)
    }

    func goTo(_ index: Int) {
        stepIndex = index
        requestScroll(for: TourStep.all[index])
    }

    /// A tour step's target must be ON SCREEN before it is
    /// spotlighted: card steps scroll the feed back to the top;
    /// Following steps scroll the list (inbox → bottom, cards → top).
    func requestScroll(for step: TourStep) {
        if step.tab == 1 && step.anchors.contains(.feedCard) {
            feedScrollTopTick += 1
        }
        if step.tab == 0 {
            if step.anchors.contains(.followingInbox) {
                followingScrollToBottom = true
            } else {
                followingScrollToBottom = false
            }
            followingScrollTick += 1
        }
    }

    /// An action step completes itself when the user performs its
    /// action — but only when the current step is waiting for exactly
    /// that action. Tapping Next instead is always available: the
    /// actions are optional, never a gate.
    func actionDone(_ action: TourAction) {
        guard active, step.action == action else { return }
        next()
    }
}

// MARK: - Tour overlay

/// The coach-mark overlay, ported from `lib/widgets/tour_overlay.dart`:
/// dims the app, cuts spotlight holes around the current step's
/// anchors, and floats the caption card near them.
///
/// - Dim: black at 0.7 (Flutter 0xB3000000), violet ring #8B5CF6,
///   rounded holes (radius 14, inflated 6).
/// - On explain-only steps it swallows every tap — the only ways
///   through are its own Skip / Back / Next buttons. On ACTION steps
///   (and tap-through steps) the one action target's rect stays OPEN:
///   the dim is drawn as four rectangles AROUND it, so the real control
///   underneath receives the gesture while everything else stays blocked.
/// - Caption: title, body, "Try it now — or tap Next to move on
///   without it." on action steps, progress dots, Skip / Back / Next
///   (first button "Let's go", last "Done"). The caption is placed
///   where it fits, never covering a live control.
struct TourOverlay: View {
    @ObservedObject var controller: TourController
    let frames: [TourAnchor: CGRect]
    let onSkip: () -> Void

    private var step: TourStep { controller.step }

    /// The spotlight holes: every mounted anchor, inflated by 6.
    private var holes: [CGRect] {
        var rects: [CGRect] = []
        for anchor in step.anchors {
            if let frame = frames[anchor] {
                rects.append(frame.insetBy(dx: -6, dy: -6))
            }
        }
        if rects.isEmpty, let fallback = step.fallback, let frame = frames[fallback] {
            rects = [frame.insetBy(dx: -6, dy: -6)]
        }
        return rects
    }

    /// The live control's rect (action / tap-through steps), inflated by 6.
    private var passRect: CGRect? {
        guard let target = step.actionTarget, let frame = frames[target] else { return nil }
        return frame.insetBy(dx: -6, dy: -6)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pass = passRect {
                    // Four dim rectangles around the live control —
                    // the control itself stays open to gestures.
                    dimRect(x: 0, y: 0, width: geometry.size.width, height: max(0, pass.minY))
                    dimRect(x: 0, y: pass.maxY, width: geometry.size.width,
                            height: max(0, geometry.size.height - pass.maxY))
                    dimRect(x: 0, y: pass.minY, width: max(0, pass.minX), height: pass.height)
                    dimRect(x: pass.maxX, y: pass.minY,
                            width: max(0, geometry.size.width - pass.maxX), height: pass.height)
                } else {
                    // Full-screen dim with holes, swallowing taps.
                    Color.black.opacity(0.7)
                        .mask(SpotlightMask(holes: holes))
                        .onTapGesture { /* swallow */ }
                }

                // Violet rings around the holes.
                ForEach(holes.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.newViolet, lineWidth: 2)
                        .frame(width: holes[index].width, height: holes[index].height)
                        .position(x: holes[index].midX, y: holes[index].midY)
                }

                caption(in: geometry.size)
            }
            .ignoresSafeArea()
        }
    }

    private func dimRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Color.black.opacity(0.7)
            .frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
            .onTapGesture { /* swallow */ }
    }

    private func caption(in size: CGSize) -> some View {
        let union = holes.reduce(nil as CGRect?) { partial, rect in
            partial?.union(rect) ?? rect
        }
        let card = captionCard
        if let union {
            let needed: CGFloat = 260
            let spaceBelow = size.height - union.maxY
            let spaceAbove = union.minY
            if spaceBelow >= needed {
                return AnyView(
                    VStack {
                        Spacer().frame(height: union.maxY + 14)
                        card
                        Spacer()
                    }
                )
            }
            if spaceAbove >= needed {
                return AnyView(
                    VStack {
                        Spacer()
                        card
                        Spacer().frame(height: size.height - union.minY + 14)
                    }
                )
            }
            // Neither side fits whole: dock on the roomier side of the
            // live control when there is one, else centre.
            if let pass = passRect {
                let above = pass.minY - 14
                let below = size.height - pass.maxY - 14
                if below >= above {
                    return AnyView(
                        VStack {
                            Spacer().frame(height: pass.maxY + 14)
                            card
                            Spacer()
                        }
                    )
                }
                return AnyView(
                    VStack {
                        Spacer()
                        card
                        Spacer().frame(height: size.height - pass.minY + 14)
                    }
                )
            }
        }
        return AnyView(
            VStack {
                Spacer()
                card
                Spacer()
            }
        )
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if controller.isFirst {
                        HStack {
                            Spacer()
                            Image("SplashLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                            Spacer()
                        }
                        .padding(.bottom, 6)
                    }
                    Text(step.title)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(step.body)
                        .font(.body)
                    if step.action != .none {
                        Text("Try it now — or tap Next to move on without it.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 2)
                    }
                }
            }

            HStack {
                Spacer()
                ForEach(0..<TourStep.all.count, id: \.self) { index in
                    Circle()
                        .fill(index == controller.stepIndex ? Color.accentColor : Color.primary.opacity(0.25))
                        .frame(width: index == controller.stepIndex ? 8 : 6,
                               height: index == controller.stepIndex ? 8 : 6)
                }
                Spacer()
            }
            .padding(.top, 14)

            HStack {
                if !controller.isLast {
                    Button("Skip", action: onSkip)
                }
                Spacer()
                if !controller.isFirst {
                    Button("Back") { controller.back() }
                }
                Button(controller.isFirst ? "Let's go" : controller.isLast ? "Done" : "Next") {
                    controller.next()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 12, trailing: 20))
        .frame(maxWidth: 360)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding(.horizontal, 16)
    }
}

/// A mask that covers the whole area except rounded-rect holes.
struct SpotlightMask: View {
    let holes: [CGRect]

    var body: some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            for hole in holes {
                path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14))
            }
            context.fill(path, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }
}

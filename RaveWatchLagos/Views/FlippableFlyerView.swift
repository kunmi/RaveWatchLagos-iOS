import SwiftUI

/// The detail page's flyer, ported from `lib/widgets/flippable_flyer.dart`.
///
/// - Front: the detail flyer full width, uncropped, natural aspect,
///   300 ms fade-in. Fail-quiet: it occupies no space before decode or
///   on error.
/// - A dog-ear fold top-right (24pt flap) ONLY when DJs are non-empty.
///   Tap the dog-ear or long-press to flip (450 ms rotateY, perspective
///   0.0012) to the back face: dark panel #14101F, "LINEUP" heading in
///   violet, the DJs in billing order, "Tap to flip back". Tap or
///   long-press the back to flip back.
/// - A single tap opens the full-screen viewer and never flips.
/// - No lineup → no dog-ear, no flip.
struct FlippableFlyerView: View {
    let event: Event
    let onOpenViewer: () -> Void

    @State private var imageData: Data?
    @State private var flipped = false
    @State private var appeared = false

    private var hasLineup: Bool { !event.djs.isEmpty }

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                ZStack {
                    // Front face.
                    flyerImage(uiImage)
                        .opacity(flipped ? 0 : 1)
                    // Back face (pre-rotated 180° so it reads correctly
                    // once the container has flipped).
                    lineupBack
                        .opacity(flipped ? 1 : 0)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    // Dog-ear fold, top-right — only with a lineup.
                    if hasLineup && !flipped {
                        dogEar
                            .onTapGesture { flip() }
                    }
                }
                .rotation3DEffect(
                    .degrees(flipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.0012
                )
                .animation(.easeInOut(duration: 0.45), value: flipped)
                .opacity(appeared ? 1 : 0)
                .animation(.easeIn(duration: 0.3), value: appeared)
                .onTapGesture {
                    // A single tap opens the viewer and never flips.
                    onOpenViewer()
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    if hasLineup { flip() }
                }
            }
        }
        .task {
            guard let url = event.detailImageURL else { return }
            imageData = await FlyerImageCache.shared.data(for: url)
            if imageData != nil {
                appeared = true
            }
        }
    }

    private func flip() {
        flipped.toggle()
    }

    private func flyerImage(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
    }

    private var lineupBack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LINEUP")
                .font(.headline)
                .foregroundStyle(Color.newViolet)
            ForEach(event.djs, id: \.self) { dj in
                Text(dj)
                    .font(.body)
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("Tap to flip back")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x1F / 255))
        .onTapGesture { flip() }
        .onLongPressGesture(minimumDuration: 0.4) { flip() }
    }

    /// The dog-ear fold: a 24pt flap, white 0.85 over a black 0.25
    /// shadow, in a 44×44 tap target at the top-right corner.
    private var dogEar: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .frame(width: 44, height: 44)
            DogEarShape()
                .fill(Color.black.opacity(0.25))
                .frame(width: 24, height: 24)
                .offset(x: 2, y: 2)
            DogEarShape()
                .fill(Color.white.opacity(0.85))
                .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// The folded-corner triangle: right angle at the top-right corner,
/// hypotenuse from the top edge to the right edge.
struct DogEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

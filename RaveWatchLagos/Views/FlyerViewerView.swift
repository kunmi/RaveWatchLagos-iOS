import SwiftUI

/// Full-screen flyer viewer, ported from
/// `lib/screens/flyer_viewer_screen.dart`.
///
/// Black backdrop, the whole UNCROPPED image fitted to the screen,
/// pinch-to-zoom (1×–4×) and pan. Back via the close button. Same
/// cache as the detail page, keyed by the same URL — the file is
/// already on the device, so opening the viewer downloads nothing a
/// second time. Fail-quiet like the detail page: if the image cannot
/// load, the viewer is just an empty black screen with its close
/// button — no broken-image icon, no error UI.
struct FlyerViewerView: View {
    let url: URL
    let onClose: () -> Void

    @State private var imageData: Data?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(4, max(1, lastScale * value))
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 {
                                    withAnimation { offset = .zero }
                                    lastOffset = .zero
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
            }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.leading, 8)
                Spacer()
            }
        }
        .task {
            imageData = await FlyerImageCache.shared.data(for: url)
        }
    }
}

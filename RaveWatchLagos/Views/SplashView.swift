import SwiftUI

/// The opening page, ported from `lib/widgets/splash_screen.dart`:
/// the logo alone on black for the first two seconds after the app
/// opens, while the stores and feed load behind it. The logo is
/// 176×176 with a 450 ms fade.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 176, height: 176)
                .opacity(appeared ? 1 : 0)
                .animation(.easeIn(duration: 0.45), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

/// The app-bar brand title, ported from `lib/widgets/brand_title.dart`:
/// the round Neon R logo (30×30) stands in for the "R", followed by
/// "aveWatchLagos".
struct BrandTitle: View {
    var body: some View {
        HStack(spacing: 0) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            Text("aveWatchLagos")
                .font(.headline)
        }
    }
}

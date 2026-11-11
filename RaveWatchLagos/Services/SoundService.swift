import AVFoundation
import Foundation

/// Swipe sounds, ported from `lib/services/swipe_sound.dart` and
/// `lib/services/sound_store.dart`.
///
/// Right swipe = HIGH click (`tick.wav`), left swipe = LOW click
/// (`click.wav`) — the same two WAV files the Android app decodes from
/// `assets/sounds/*.base64` and preloads behind the splash, so they are
/// fully loaded before the first swipe can happen. Sounds also play on
/// Following/Attending tab swipes (tick = Share, click = Delete).
/// No audio focus: playback mixes with other audio, never pauses it.
/// The on/off switch lives in Settings (`ui.soundsOn`, default on).
@MainActor
final class SoundService: ObservableObject {
    private enum Key {
        static let soundsOn = "ui.soundsOn"
    }

    @Published var soundsOn = true {
        didSet {
            defaults.set(soundsOn, forKey: Key.soundsOn)
            mirror.writeKey(Key.soundsOn, soundsOn)
        }
    }

    private var tickPlayer: AVAudioPlayer?
    private var clickPlayer: AVAudioPlayer?
    private var preloaded = false

    private let defaults: UserDefaults
    private let mirror = SettingsMirror()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.soundsOn) == nil {
            if let mirrored = mirror.readAll()[Key.soundsOn] as? Bool {
                soundsOn = mirrored
                defaults.set(mirrored, forKey: Key.soundsOn)
            }
        } else {
            soundsOn = defaults.bool(forKey: Key.soundsOn)
        }
    }

    /// Loads both click files now (called behind the splash), so the
    /// first swipe never waits on a decode.
    func preload() {
        guard !preloaded else { return }
        preloaded = true
        // Mix with other audio; never pause it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        tickPlayer = player(for: "tick")
        clickPlayer = player(for: "click")
    }

    private func player(for name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    /// The HIGH click — a right swipe (Follow / Share).
    func playTick() {
        guard soundsOn else { return }
        preload()
        tickPlayer?.currentTime = 0
        tickPlayer?.play()
    }

    /// The LOW click — a left swipe (Attend / Delete).
    func playClick() {
        guard soundsOn else { return }
        preload()
        clickPlayer?.currentTime = 0
        clickPlayer?.play()
    }
}

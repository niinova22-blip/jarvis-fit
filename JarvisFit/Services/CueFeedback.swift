import AVFoundation
import UIKit
import JarvisCore

/// Plays the synthesised cue tones (JarvisCore.CueSound) and matching haptics during live workouts.
/// Players are prepared once so a rep blip starts without delay. Uses the app's shared audio
/// session (configured by VoiceCoordinator), so tones mix with NOVA's voice.
@MainActor
final class CueFeedback {
    var soundsEnabled = true
    var hapticsEnabled = true

    private var players: [CueSound: AVAudioPlayer] = [:]
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    init() {
        for sound in CueSound.allCases {
            guard let player = try? AVAudioPlayer(data: sound.wavData(amplitude: 0.55)) else { continue }
            player.volume = sound == .rep ? 0.55 : 0.75
            player.prepareToPlay()
            players[sound] = player
        }
        light.prepare()
        notification.prepare()
    }

    func play(for cue: CoachCue) {
        guard let sound = CueSound.sound(for: cue) else { return }
        if soundsEnabled, let player = players[sound] {
            player.currentTime = 0
            player.play()
        }
        guard hapticsEnabled else { return }
        switch sound {
        case .rep: light.impactOccurred()
        case .countdown: rigid.impactOccurred(intensity: 0.6)
        case .go: rigid.impactOccurred()
        case .setComplete, .workoutComplete: notification.notificationOccurred(.success)
        }
        light.prepare()
    }
}

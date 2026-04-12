import Foundation
import AppKit

/// Simple sound effects using system sounds
final class SoundManager {
    static let shared = SoundManager()

    enum Sound: String {
        case sessionStart
        case sessionComplete
        case approvalNeeded
        case approved
        case denied
    }

    func play(_ sound: Sound) {
        guard UserDefaults.standard.object(forKey: "soundEnabled") == nil
            || UserDefaults.standard.bool(forKey: "soundEnabled") else { return }

        let selected = UserDefaults.standard.string(forKey: "selectedSound") ?? "Tink"

        // Use selected sound for most events, specific sounds for important ones
        let name: NSSound.Name
        switch sound {
        case .sessionStart:     name = NSSound.Name(selected)
        case .sessionComplete:  name = "Glass"
        case .approvalNeeded:   name = "Sosumi"
        case .approved:         name = "Pop"
        case .denied:           name = "Basso"
        }

        NSSound(named: name)?.play()
    }
}

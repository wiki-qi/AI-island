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

        let name: String
        switch sound {
        case .sessionStart:     name = selected
        case .sessionComplete:  name = "Glass"
        case .approvalNeeded:   name = "Sosumi"
        case .approved:         name = "Pop"
        case .denied:           name = "Basso"
        }

        // Use file path to avoid FSFindFolder errors in non-bundled apps
        DispatchQueue.main.async {
            let path = "/System/Library/Sounds/\(name).aiff"
            if let s = NSSound(contentsOfFile: path, byReference: true) {
                s.play()
            }
        }
    }
}

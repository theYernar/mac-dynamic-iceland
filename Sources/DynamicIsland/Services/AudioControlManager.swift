import AppKit
import Combine

/// Системная громкость для музыкального плеера.
@MainActor
public final class AudioControlManager: ObservableObject {
    @Published public private(set) var volume: Double = 0.5
    @Published public private(set) var isMuted: Bool = false

    private let commandQueue = DispatchQueue(label: "com.yernar.DynamicIsland.audioControl", qos: .utility)
    private var stateRevision: UInt = 0

    public init() {
        syncCurrentAudioState()
    }

    public func syncCurrentAudioState() {
        let revision = stateRevision
        commandQueue.async { [weak self] in
            var error: NSDictionary?
            let source = "return (output volume of (get volume settings) as string) & \"|\" & (output muted of (get volume settings) as string)"
            guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue,
                  error == nil else { return }
            let parts = result.components(separatedBy: "|")
            guard parts.count == 2, let volume = Double(parts[0]), volume.isFinite else { return }
            let muted = parts[1].lowercased() == "true"
            DispatchQueue.main.async {
                guard let self, self.stateRevision == revision else { return }
                self.volume = min(max(volume / 100.0, 0), 1)
                self.isMuted = muted
            }
        }
    }

    public func setSystemVolume(_ newValue: Double) {
        guard newValue.isFinite else { return }
        stateRevision &+= 1
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        let intVolume = Int(clamped * 100)
        isMuted = intVolume == 0
        commandQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "set volume output volume \(intVolume) output muted \(intVolume == 0)")?
                .executeAndReturnError(&error)
        }
    }

    public func toggleMute() {
        stateRevision &+= 1
        isMuted.toggle()
        let targetMute = isMuted
        commandQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "set volume output muted \(targetMute)")?.executeAndReturnError(&error)
        }
    }
}

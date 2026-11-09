import AppKit
import Foundation

/// Прямое управление Spotify и Apple Music через AppleScript.
///
/// Зачем: MediaRemote в современных macOS доставляет команды Play/Pause/Next
/// только «выбранному системой» Now Playing приложению и игнорирует адресата.
/// AppleScript же адресуется конкретному приложению по bundle id, поэтому
/// Spotify и Apple Music управляются полностью независимо друг от друга и от браузеров.
final class MusicAppScripting: @unchecked Sendable {
    struct State: Sendable {
        let isPlaying: Bool
        let isStopped: Bool
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let artworkURL: String
    }
    
    enum Command: Sendable, Equatable {
        case play, pause, next, previous
        case seek(Double)
    }
    
    enum ResultStatus: Sendable {
        case ok
        case permissionDenied
        case failed
    }
    
    static let scriptableBundleIds: [String] = ["com.spotify.client", "com.apple.Music"]
    
    static func isScriptable(_ bundleId: String) -> Bool {
        scriptableBundleIds.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
    }
    
    static func isRunning(_ bundleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleId) == .orderedSame
        }
    }
    
    /// NSAppleScript не потокобезопасен — используем один последовательный поток.
    private let queue = DispatchQueue(label: "dynamicisland.applescript", qos: .userInitiated)
    private var compiledStateScripts: [String: NSAppleScript] = [:]
    
    // MARK: - Опрос состояния
    
    func fetchState(bundleId: String, completion: @escaping @Sendable (State?, ResultStatus) -> Void) {
        // Никогда не обращаемся к незапущенному приложению: AppleScript запустил бы его.
        guard Self.isScriptable(bundleId), Self.isRunning(bundleId) else {
            completion(nil, .failed)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let isSpotify = bundleId.lowercased() == "com.spotify.client"
            let source = isSpotify ? Self.spotifyStateSource : Self.musicStateSource
            let (output, status) = self.run(source: source, cacheKey: bundleId)
            guard status == .ok, let output else {
                completion(nil, status)
                return
            }
            completion(Self.parseState(output, durationInMilliseconds: isSpotify), .ok)
        }
    }
    
    // MARK: - Команды
    
    func send(_ command: Command, to bundleId: String, completion: @escaping @Sendable (ResultStatus) -> Void) {
        guard Self.isScriptable(bundleId), Self.isRunning(bundleId) else {
            completion(.failed)
            return
        }
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let seconds):
            verb = String(format: "set player position to %.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
        }
        let source = "tell application id \"\(bundleId)\" to \(verb)"
        queue.async { [weak self] in
            guard let self else { return }
            let (_, status) = self.run(source: source, cacheKey: nil)
            completion(status)
        }
    }
    
    // MARK: - Внутреннее
    
    private func run(source: String, cacheKey: String?) -> (String?, ResultStatus) {
        let script: NSAppleScript
        if let key = cacheKey, let cached = compiledStateScripts[key] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return (nil, .failed) }
            if let key = cacheKey { compiledStateScripts[key] = created }
            script = created
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: пользователь запретил автоматизацию; -1744: требуется согласие
            if code == -1743 || code == -1744 { return (nil, .permissionDenied) }
            return (nil, .failed)
        }
        return (result.stringValue, .ok)
    }
    
    private static func parseState(_ output: String, durationInMilliseconds: Bool) -> State {
        let parts = output.components(separatedBy: "\n")
        let stateStr = parts.first?.lowercased() ?? "stopped"
        func field(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
        // AppleScript форматирует числа по локали системы (например «12,5»)
        func number(_ i: Int) -> Double {
            Double(field(i).replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
        }
        var duration = number(4)
        if durationInMilliseconds { duration /= 1000.0 }
        return State(
            isPlaying: stateStr == "playing",
            isStopped: stateStr == "stopped" || parts.count < 6,
            title: field(1),
            artist: field(2),
            album: field(3),
            duration: duration,
            position: number(5),
            artworkURL: field(6)
        )
    }
    
    private static let spotifyStateSource = """
    tell application id "com.spotify.client"
        set st to (player state as string)
        if st is "stopped" then return st
        set t to current track
        set d to linefeed
        return st & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as string) & d & ((player position) as string) & d & (artwork url of t)
    end tell
    """
    
    private static let musicStateSource = """
    tell application id "com.apple.Music"
        set st to (player state as string)
        if st is "stopped" then return st
        set t to current track
        set d to linefeed
        return st & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as string) & d & ((player position) as string) & d & ""
    end tell
    """
}


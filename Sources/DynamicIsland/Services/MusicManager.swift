import AppKit
import Combine
import SwiftUI

public enum MusicPlayerSource: Equatable {
    case spotify
    case appleMusic
    case browser(name: String, bundleId: String)
    case app(name: String, bundleId: String)
    case system
    
    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .browser(let name, _): return name
        case .app(let name, _): return name
        case .system: return "System Player"
        }
    }
    
    public var bundleIdentifier: String? {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        case .browser(_, let id): return id
        case .app(_, let id): return id
        case .system: return nil
        }
    }
    
    public var iconName: String {
        switch self {
        case .spotify: return "waveform.circle.fill"
        case .appleMusic: return "music.note"
        case .browser: return "globe"
        case .app: return "play.rectangle.fill"
        case .system: return "play.tv.fill"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .spotify:
            return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .appleMusic:
            return Color(red: 0.98, green: 0.24, blue: 0.36)
        case .browser(let name, _):
            let lower = name.lowercased()
            if lower.contains("firefox") {
                return Color(red: 1.0, green: 0.45, blue: 0.15)
            } else if lower.contains("safari") {
                return Color(red: 0.15, green: 0.62, blue: 0.98)
            } else if lower.contains("chrome") || lower.contains("\u{44F}\u{43D}\u{434}\u{435}\u{43A}\u{441}") || lower.contains("yandex") {
                return Color(red: 0.98, green: 0.72, blue: 0.18)
            } else {
                return Color(red: 0.45, green: 0.58, blue: 0.98)
            }
        case .app, .system:
            return Color(red: 0.38, green: 0.62, blue: 0.98)
        }
    }
    
    public static func from(bundleId: String?, displayName: String?) -> MusicPlayerSource {
        guard let bundleId, !bundleId.isEmpty else { return .system }
        let lower = bundleId.lowercased()
        if lower == "com.spotify.client" {
            return .spotify
        } else if lower == "com.apple.music" {
            return .appleMusic
        } else if lower.contains("firefox") {
            return .browser(name: "Firefox", bundleId: bundleId)
        } else if lower.contains("safari") {
            return .browser(name: "Safari", bundleId: bundleId)
        } else if lower.contains("chrome") {
            return .browser(name: "Chrome", bundleId: bundleId)
        } else if lower.contains("arc") || lower.contains("thebrowser") {
            return .browser(name: "Arc", bundleId: bundleId)
        } else if lower.contains("brave") {
            return .browser(name: "Brave", bundleId: bundleId)
        } else if lower.contains("yandex") {
            return .browser(name: "Yandex", bundleId: bundleId)
        } else if lower.contains("edgemac") {
            return .browser(name: "Edge", bundleId: bundleId)
        } else if lower.contains("opera") {
            return .browser(name: "Opera", bundleId: bundleId)
        } else {
            let resolvedName = (displayName?.isEmpty == false ? displayName : nil) ?? Self.appName(for: bundleId) ?? "Media"
            return .app(name: resolvedName, bundleId: bundleId)
        }
    }
    
    private static func appName(for bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Представляет отдельную доступную медиа-сессию (например, Firefox, Spotify, Apple Music, Chrome и т.д.)
public struct MediaSession: Identifiable, Equatable {
    public let id: String // bundleIdentifier
    public let source: MusicPlayerSource
    public var isPlaying: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var currentTime: Double
    public var artworkImage: NSImage?
    public var appIconImage: NSImage?
}

@MainActor
public final class MusicManager: ObservableObject {
    /// Все доступные аудио-источники в данный момент (например, [Spotify, Firefox])
    @Published public var sessions: [MediaSession] = []
    /// Идентификатор выбранного пользователем источника
    @Published public private(set) var selectedSessionId: String? = nil
    
    /// Текущие свойства активного (выбранного) источника для отображения в плеере
    @Published public var isPlaying: Bool = false
    @Published public var trackTitle: String = "Not Playing"
    @Published public var trackArtist: String = "Play audio in a browser, Spotify, or Apple Music"
    @Published public var trackAlbum: String = ""
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var artworkImage: NSImage? = nil
    @Published public var appIconImage: NSImage? = nil
    @Published public var activeSource: MusicPlayerSource = .system
    @Published public private(set) var playbackError: String? = nil

    typealias ScriptingCommandSender = (MusicAppScripting.Command, String, @escaping @Sendable (MusicAppScripting.ResultStatus) -> Void) -> Void
    private let helperCommandSender: (([String: Any]) -> Bool)?
    private let scriptingCommandSender: ScriptingCommandSender
    private var latestCommandIds: [String: String] = [:]
    
    private var helperProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
    private var artworkCache: [String: NSImage] = [:]
    private var appIconCache: [String: NSImage] = [:]
    
    public convenience init() {
        self.init(startHelper: true)
    }

    // Dependencies are injectable so routing can be checked without controlling real apps.
    init(helperCommandSender: (([String: Any]) -> Bool)? = nil,
         scriptingCommandSender: ScriptingCommandSender? = nil,
         startHelper: Bool = false) {
        self.helperCommandSender = helperCommandSender
        let scripting = MusicAppScripting()
        self.scriptingCommandSender = scriptingCommandSender ?? { command, bundleId, completion in
            scripting.send(command, to: bundleId, completion: completion)
        }
        if startHelper { startHelperProcess() }
    }
    
    /// Выбрать конкретный источник аудио (например, переключиться между Spotify и Firefox)
    public func selectSession(id: String) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        selectedSessionId = id
        playbackError = nil
        applySelectedSessionToPublishedProperties(session)
    }
    
    public func refreshNowPlaying() {
        sendHelperCommand(["action": "poll"])
    }
    
    private func resolveHelperScriptPath() -> String? {
        if let bundled = Bundle.main.path(forResource: "MediaRemoteHelper", ofType: "swift") {
            return bundled
        }
        let localPath = "Resources/MediaRemoteHelper.swift"
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let relResources = execDir.appendingPathComponent("../Resources/MediaRemoteHelper.swift").standardized.path
        if FileManager.default.fileExists(atPath: relResources) {
            return relResources
        }
        return nil
    }
    
    private func startHelperProcess() {
        guard helperProcess?.isRunning != true else { return }
        clearHelperConnection()
        guard let scriptPath = resolveHelperScriptPath() else { return }
        
        let proc = Process()
        let xcodeSwift = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
        let cltSwift = "/Library/Developer/CommandLineTools/usr/bin/swift"
        if FileManager.default.isExecutableFile(atPath: xcodeSwift) {
            proc.executableURL = URL(fileURLWithPath: xcodeSwift)
        } else if FileManager.default.isExecutableFile(atPath: cltSwift) {
            proc.executableURL = URL(fileURLWithPath: cltSwift)
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        }
        
        proc.arguments = [
            "-module-cache-path", "/tmp/swift-module-cache",
            scriptPath
        ]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.helperProcess = proc
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self, weak proc] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                guard let self, let proc, self.helperProcess === proc else { return }
                self.processIncomingStdoutData(data)
            }
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard self?.helperProcess === terminatedProcess else { return }
                self?.clearHelperConnection()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.startHelperProcess()
            }
        }

        do {
            try proc.run()
        } catch {
            clearHelperConnection()
        }
    }

    private func clearHelperConnection() {
        helperProcess?.terminationHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdinPipe?.fileHandleForReading.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stdoutPipe?.fileHandleForWriting.close()
        helperProcess = nil
        stdinPipe = nil
        stdoutPipe = nil
        stdoutBuffer.removeAll(keepingCapacity: true)
    }

    func processIncomingStdoutChunk(_ chunk: String) {
        processIncomingStdoutData(Data(chunk.utf8))
    }

    func processIncomingStdoutData(_ data: Data) {
        // A pipe read may end inside a UTF-8 scalar; decode only complete JSON lines.
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let rawLine = stdoutBuffer[..<newline]
            let line = String(data: rawLine, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            stdoutBuffer.removeSubrange(...newline)
            if let line, !line.isEmpty {
                parseHelperJSONLine(line)
            }
        }
    }
    
    private func parseHelperJSONLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let event = root["event"] as? String {
            handleCommandEvent(event, payload: root)
            return
        }
        guard let rawSessions = root["sessions"] as? [[String: Any]] else { return }

        var parsed: [MediaSession] = []
        for item in rawSessions {
            guard let bundleId = item["bundleId"] as? String,
                  let title = item["title"] as? String,
                  !title.isEmpty else {
                continue
            }
            let displayName = item["displayName"] as? String
            let source = MusicPlayerSource.from(bundleId: bundleId, displayName: displayName)
            let artist = (item["artist"] as? String) ?? ""
            let album = (item["album"] as? String) ?? ""
            let duration = (item["duration"] as? Double) ?? 0.0
            let elapsed = (item["elapsed"] as? Double) ?? 0.0
            let isPlaying = (item["isPlaying"] as? Bool) ?? false
            let artworkPath = (item["artworkPath"] as? String) ?? ""
            
            let cacheKey = "\(bundleId)|\(title)"
            var artImg = artworkCache[cacheKey]
            if artImg == nil && !artworkPath.isEmpty {
                if let loaded = NSImage(contentsOfFile: artworkPath) {
                    artImg = loaded
                    artworkCache[cacheKey] = loaded
                }
            }
            
            let appIcon = resolveAppIcon(for: bundleId)
            parsed.append(
                MediaSession(
                    id: bundleId,
                    source: source,
                    isPlaying: isPlaying,
                    title: title,
                    artist: !artist.isEmpty ? artist : source.displayName,
                    album: album,
                    duration: duration,
                    currentTime: elapsed,
                    artworkImage: artImg,
                    appIconImage: appIcon
                )
            )
        }
        
        // Сортируем: музыкальные плееры (Spotify / Apple Music) первыми, затем браузеры
        let sorted = parsed.sorted { a, b in
            let aPriority = (a.source == .spotify || a.source == .appleMusic) ? 0 : 1
            let bPriority = (b.source == .spotify || b.source == .appleMusic) ? 0 : 1
            if aPriority != bPriority { return aPriority < bPriority }
            return a.source.displayName < b.source.displayName
        }
        
        self.sessions = sorted
        
        if let selectedId = self.selectedSessionId,
           let matching = sorted.first(where: { $0.id == selectedId }) {
            // A state update must never move controls away from the selected app.
            self.applySelectedSessionToPublishedProperties(matching)
        } else if let playingSession = sorted.first(where: { $0.isPlaying }) ?? sorted.first {
            self.selectedSessionId = playingSession.id
            self.playbackError = nil
            self.applySelectedSessionToPublishedProperties(playingSession)
        } else {
            resetSelectedSession()
        }
    }

    private func resetSelectedSession() {
        selectedSessionId = nil
        activeSource = .system
        isPlaying = false
        trackTitle = "Not Playing"
        trackArtist = "Play audio in a browser, Spotify, or Apple Music"
        trackAlbum = ""
        duration = 0
        currentTime = 0
        artworkImage = nil
        appIconImage = nil
        playbackError = nil
        latestCommandIds.removeAll()
    }

    private func handleCommandEvent(_ event: String, payload: [String: Any]) {
        guard event == "commandResult" || event == "commandRejected" || event == "commandFailed",
              let bundleId = payload["bundleId"] as? String,
              selectedSessionId == bundleId else { return }
        if let requestId = payload["requestId"] as? String,
           latestCommandIds[bundleId] != requestId { return }
        if event == "commandResult", payload["success"] as? Bool == true {
            playbackError = nil
        } else {
            playbackError = (payload["message"] as? String) ?? "Could not control \(activeSource.displayName). Try again."
        }
    }

    private func applySelectedSessionToPublishedProperties(_ session: MediaSession) {
        self.activeSource = session.source
        self.isPlaying = session.isPlaying
        self.trackTitle = session.title
        self.trackArtist = session.artist
        self.trackAlbum = session.album
        self.duration = session.duration
        self.currentTime = session.currentTime
        self.artworkImage = session.artworkImage ?? self.artworkCache["\(session.id)|\(session.title)"]
        self.appIconImage = session.appIconImage
    }
    
    private func resolveAppIcon(for bundleId: String) -> NSImage? {
        if let cached = appIconCache[bundleId] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        appIconCache[bundleId] = icon
        return icon
    }
    
    // MARK: - Управление воспроизведением выбранного источника
    
    private var currentSelectedSession: MediaSession? {
        if let id = selectedSessionId {
            return sessions.first(where: { $0.id == id })
        }
        return sessions.first
    }
    
    @discardableResult
    private func sendHelperCommand(_ dict: [String: Any]) -> Bool {
        if let helperCommandSender { return helperCommandSender(dict) }
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let line = String(data: data, encoding: .utf8),
              let lineData = (line + "\n").data(using: .utf8) else { return false }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: lineData)
            return true
        } catch {
            return false
        }
    }

    public func togglePlayPause() {
        guard let session = currentSelectedSession else { return }
        // Explicit play/pause is safe if a delayed poll still describes the old state.
        let action = session.isPlaying ? "pause" : "play"
        sendPlaybackCommand(action, scriptingCommand: session.isPlaying ? .pause : .play)
    }

    public func nextTrack() {
        sendPlaybackCommand("next", scriptingCommand: .next)
    }

    public func previousTrack() {
        sendPlaybackCommand("previous", scriptingCommand: .previous)
    }

    public func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let target = max(0, seconds)
        sendPlaybackCommand("seek", scriptingCommand: .seek(target), seconds: target)
    }

    private func sendPlaybackCommand(_ action: String, scriptingCommand: MusicAppScripting.Command, seconds: Double? = nil) {
        guard let session = currentSelectedSession else { return }
        let bundleId = session.id
        let requestId = UUID().uuidString
        latestCommandIds[bundleId] = requestId
        playbackError = nil

        if MusicAppScripting.isScriptable(bundleId) {
            // Never fall back to system media commands: they may control a different app.
            scriptingCommandSender(scriptingCommand, bundleId) { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if self.latestCommandIds[bundleId] == requestId {
                        if status == .ok {
                            self.applySuccessfulCommand(action, seconds: seconds, to: bundleId)
                        } else if self.selectedSessionId == bundleId {
                            self.playbackError = status == .permissionDenied
                                ? "Allow control of \(session.source.displayName) in System Settings → Privacy & Security → Automation."
                                : "Could not send the command to \(session.source.displayName)."
                        }
                    }
                    self.refreshNowPlaying()
                }
            }
        } else {
            var payload: [String: Any] = ["action": action, "bundleId": bundleId, "requestId": requestId]
            if let seconds { payload["seconds"] = seconds }
            if !sendHelperCommand(payload) {
                playbackError = "Could not send the command to \(session.source.displayName)."
            }
        }
    }

    private func applySuccessfulCommand(_ action: String, seconds: Double?, to bundleId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == bundleId }) else { return }
        switch action {
        case "play": sessions[index].isPlaying = true
        case "pause": sessions[index].isPlaying = false
        case "seek":
            if let seconds { sessions[index].currentTime = seconds }
        default: break
        }
        if selectedSessionId == bundleId {
            playbackError = nil
            applySelectedSessionToPublishedProperties(sessions[index])
        }
    }

    public func openActiveMusicApp() {
        if let bundleId = activeSource.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

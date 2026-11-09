import XCTest
@testable import DynamicIsland

final class MusicManagerTests: XCTestCase {
    private let spotify = "com.spotify.client"
    private let firefox = "org.mozilla.firefox"

    @MainActor
    private final class Recorder {
        struct ScriptRequest {
            let command: MusicAppScripting.Command
            let bundleId: String
            let completion: @Sendable (MusicAppScripting.ResultStatus) -> Void
        }

        var helperCommands: [[String: Any]] = []
        var scriptRequests: [ScriptRequest] = []
        var helperAvailable = true
        var didPoll: XCTestExpectation?

        func makeManager() -> MusicManager {
            MusicManager(helperCommandSender: { [self] payload in
                helperCommands.append(payload)
                if payload["action"] as? String == "poll" { didPoll?.fulfill() }
                return helperAvailable
            }, scriptingCommandSender: { [self] command, bundleId, completion in
                scriptRequests.append(ScriptRequest(command: command, bundleId: bundleId, completion: completion))
            })
        }

        var playbackCommands: [[String: Any]] {
            helperCommands.filter { $0["action"] as? String != "poll" }
        }
    }

    @MainActor
    private func emit(_ payload: [String: Any], to manager: MusicManager) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        manager.processIncomingStdoutChunk(String(decoding: data, as: UTF8.self) + "\n")
    }

    @MainActor
    private func emitSessions(to manager: MusicManager, spotifyPlaying: Bool, firefoxPlaying: Bool) throws {
        try emit(["sessions": [
            ["bundleId": spotify, "title": "Spotify track", "isPlaying": spotifyPlaying, "duration": 120, "elapsed": 12],
            ["bundleId": firefox, "title": "Firefox video", "isPlaying": firefoxPlaying, "duration": 240, "elapsed": 24]
        ]], to: manager)
    }

    @MainActor
    func testSpotifyPauseThenFirefoxPlayTargetsFirefox() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: true, firefoxPlaying: false)
        manager.togglePlayPause()

        XCTAssertEqual(recorder.scriptRequests.count, 1)
        XCTAssertEqual(recorder.scriptRequests[0].bundleId, spotify)
        XCTAssertEqual(recorder.scriptRequests[0].command, .pause)
        XCTAssertTrue(manager.isPlaying, "A send alone must not change displayed state")

        let poll = expectation(description: "Refresh after Spotify pause")
        recorder.didPoll = poll
        recorder.scriptRequests[0].completion(.ok)
        await fulfillment(of: [poll], timeout: 1)
        XCTAssertFalse(manager.isPlaying)

        manager.selectSession(id: firefox)
        manager.togglePlayPause()
        XCTAssertEqual(recorder.playbackCommands.count, 1)
        XCTAssertEqual(recorder.playbackCommands[0]["bundleId"] as? String, firefox)
        XCTAssertEqual(recorder.playbackCommands[0]["action"] as? String, "play")
        XCTAssertEqual(recorder.scriptRequests.count, 1)
        XCTAssertFalse(manager.isPlaying, "Browser state must wait for the helper poll")
    }

    @MainActor
    func testFirefoxPauseThenSpotifyPlayTargetsSpotify() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: true)
        manager.togglePlayPause()
        XCTAssertEqual(recorder.playbackCommands[0]["bundleId"] as? String, firefox)
        XCTAssertEqual(recorder.playbackCommands[0]["action"] as? String, "pause")

        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: spotify)
        manager.togglePlayPause()
        XCTAssertEqual(recorder.scriptRequests.count, 1)
        XCTAssertEqual(recorder.scriptRequests[0].bundleId, spotify)
        XCTAssertEqual(recorder.scriptRequests[0].command, .play)
        XCTAssertEqual(recorder.playbackCommands.count, 1)
    }

    @MainActor
    func testPollCannotReplaceSelectedPausedSourceWithPlayingApp() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: firefox)
        try emitSessions(to: manager, spotifyPlaying: true, firefoxPlaying: false)
        XCTAssertEqual(manager.selectedSessionId, firefox)
        XCTAssertEqual(manager.trackTitle, "Firefox video")
        XCTAssertFalse(manager.isPlaying)
        manager.togglePlayPause()
        XCTAssertEqual(recorder.playbackCommands.last?["bundleId"] as? String, firefox)

        manager.selectSession(id: spotify)
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: true)
        XCTAssertEqual(manager.selectedSessionId, spotify)
        XCTAssertFalse(manager.isPlaying)
    }

    @MainActor
    func testScriptingFailureReportsErrorWithoutFallbackOrFakePlayback() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: true)
        manager.selectSession(id: spotify)
        manager.togglePlayPause()
        let poll = expectation(description: "Refresh after permission rejection")
        recorder.didPoll = poll
        recorder.scriptRequests[0].completion(.permissionDenied)
        await fulfillment(of: [poll], timeout: 1)

        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.selectedSessionId, spotify)
        XCTAssertTrue(manager.playbackError?.contains("Automation") == true)
        XCTAssertTrue(recorder.playbackCommands.isEmpty)
    }

    @MainActor
    func testLateScriptingSuccessUpdatesOriginalSessionWithoutChangingSelection() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: spotify)
        manager.togglePlayPause()
        manager.selectSession(id: firefox)

        let poll = expectation(description: "Refresh after delayed Spotify command")
        recorder.didPoll = poll
        recorder.scriptRequests[0].completion(.ok)
        await fulfillment(of: [poll], timeout: 1)

        XCTAssertEqual(manager.selectedSessionId, firefox)
        XCTAssertEqual(manager.trackTitle, "Firefox video")
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.sessions.first(where: { $0.id == spotify })?.isPlaying, true)
    }

    @MainActor
    func testRejectedBrowserCommandAndDisconnectedHelperDoNotChangePlayback() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: firefox)
        manager.togglePlayPause()
        let request = try XCTUnwrap(recorder.playbackCommands.last)
        try emit([
            "event": "commandResult", "bundleId": firefox,
            "requestId": try XCTUnwrap(request["requestId"] as? String),
            "success": false, "message": "Firefox is unavailable"
        ], to: manager)
        XCTAssertEqual(manager.playbackError, "Firefox is unavailable")
        XCTAssertFalse(manager.isPlaying)

        recorder.helperAvailable = false
        manager.togglePlayPause()
        XCTAssertNotNil(manager.playbackError)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertTrue(recorder.scriptRequests.isEmpty)
    }

    @MainActor
    func testErrorsFromPreviouslySelectedAppDoNotReplaceCurrentSourceState() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: firefox)
        manager.togglePlayPause()
        manager.selectSession(id: spotify)
        try emit(["event": "commandRejected", "bundleId": firefox, "message": "Old failure"], to: manager)
        XCTAssertNil(manager.playbackError)
        XCTAssertEqual(manager.selectedSessionId, spotify)
    }

    @MainActor
    func testAllTransportControlsUseSelectedApplicationAndExplicitActions() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: spotify)
        manager.nextTrack()
        manager.previousTrack()
        manager.seek(to: 31)
        XCTAssertEqual(recorder.scriptRequests.map(\.command), [.next, .previous, .seek(31)])
        XCTAssertTrue(recorder.scriptRequests.allSatisfy { $0.bundleId == spotify })

        manager.selectSession(id: firefox)
        manager.nextTrack()
        manager.previousTrack()
        manager.seek(to: 42)
        XCTAssertEqual(recorder.playbackCommands.compactMap { $0["action"] as? String }, ["next", "previous", "seek"])
        XCTAssertTrue(recorder.playbackCommands.allSatisfy { $0["bundleId"] as? String == firefox })
        XCTAssertEqual(recorder.playbackCommands.last?["seconds"] as? Double, 42)
        XCTAssertEqual(manager.currentTime, 24, "Seeking waits for confirmation")
    }

    @MainActor
    func testAppleMusicUsesDirectScripting() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emit(["sessions": [["bundleId": "com.apple.Music", "title": "Music track", "isPlaying": false]]], to: manager)
        manager.togglePlayPause()
        XCTAssertEqual(recorder.scriptRequests.first?.bundleId, "com.apple.Music")
        XCTAssertEqual(recorder.scriptRequests.first?.command, .play)
        XCTAssertTrue(recorder.playbackCommands.isEmpty)
    }

    @MainActor
    func testInvalidSelectionAndEmptySessionsCannotControlStaleApplication() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: true)
        manager.selectSession(id: "missing.app")
        XCTAssertEqual(manager.selectedSessionId, firefox)

        try emit(["sessions": []], to: manager)
        XCTAssertNil(manager.selectedSessionId)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.activeSource, .system)
        XCTAssertEqual(manager.duration, 0)
        XCTAssertEqual(manager.trackTitle, "Not Playing")
        manager.togglePlayPause()
        manager.nextTrack()
        manager.seek(to: 10)
        XCTAssertTrue(recorder.playbackCommands.isEmpty)
        XCTAssertTrue(recorder.scriptRequests.isEmpty)
    }

    @MainActor
    func testHelperMessagesCanArriveInPartialChunks() async throws {
        let manager = Recorder().makeManager()
        manager.processIncomingStdoutChunk("{\"sessions\":[{\"bundleId\":\"org.mozilla.")
        XCTAssertTrue(manager.sessions.isEmpty)
        manager.processIncomingStdoutChunk("firefox\",\"title\":\"Video\",\"isPlaying\":false}]}\n")
        XCTAssertEqual(manager.selectedSessionId, firefox)
        XCTAssertEqual(manager.trackTitle, "Video")
    }

    @MainActor
    func testUTF8ScalarsCanBeSplitAcrossHelperPipeReads() async throws {
        let manager = Recorder().makeManager()
        let message = Data("{\"sessions\":[{\"bundleId\":\"org.mozilla.firefox\",\"title\":\"\u{41C}\u{443}\u{437}\u{44B}\u{43A}\u{430} 🎵\",\"isPlaying\":false}]}\n".utf8)
        // Deliver one byte at a time, including the middle of Cyrillic and emoji scalars.
        for byte in message.dropLast() {
            manager.processIncomingStdoutData(Data([byte]))
        }
        XCTAssertTrue(manager.sessions.isEmpty)
        manager.processIncomingStdoutData(Data(message.suffix(1)))
        XCTAssertEqual(manager.selectedSessionId, firefox)
        XCTAssertEqual(manager.trackTitle, "\u{41C}\u{443}\u{437}\u{44B}\u{43A}\u{430} 🎵")
    }

    @MainActor
    func testOldRequestResultCannotOverwriteNewerResultForSameSource() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: firefox)
        manager.togglePlayPause()
        let oldId = try XCTUnwrap(recorder.playbackCommands.last?["requestId"] as? String)
        manager.nextTrack()
        let currentId = try XCTUnwrap(recorder.playbackCommands.last?["requestId"] as? String)

        try emit(["event": "commandResult", "bundleId": firefox, "requestId": currentId,
                  "success": false, "message": "Current command failed"], to: manager)
        for success in [true, false] {
            try emit(["event": "commandResult", "bundleId": firefox, "requestId": oldId,
                      "success": success, "message": "Old command failed"], to: manager)
            XCTAssertEqual(manager.playbackError, "Current command failed")
        }
        XCTAssertFalse(manager.isPlaying)
    }

    @MainActor
    func testLateScriptingFailureDoesNotOverwriteNewSelectedSourceError() async throws {
        let recorder = Recorder()
        let manager = recorder.makeManager()
        try emitSessions(to: manager, spotifyPlaying: false, firefoxPlaying: false)
        manager.selectSession(id: spotify)
        manager.togglePlayPause()
        manager.selectSession(id: firefox)
        manager.togglePlayPause()
        let requestId = try XCTUnwrap(recorder.playbackCommands.last?["requestId"] as? String)
        try emit(["event": "commandResult", "bundleId": firefox, "requestId": requestId,
                  "success": false, "message": "Firefox command failed"], to: manager)

        let poll = expectation(description: "Refresh after delayed failure")
        recorder.didPoll = poll
        recorder.scriptRequests[0].completion(.permissionDenied)
        await fulfillment(of: [poll], timeout: 1)
        XCTAssertEqual(manager.selectedSessionId, firefox)
        XCTAssertEqual(manager.playbackError, "Firefox command failed")
        XCTAssertFalse(manager.isPlaying)
    }
}

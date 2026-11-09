#!/usr/bin/env python3
"""Exercise the production helper command handlers with an isolated MediaRemote stub.

No user applications or system media sessions are controlled by this test.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
helper = (root / "Resources/MediaRemoteHelper.swift").read_text()
handlers = helper[helper.index("func commandCode("):helper.index("\nregisterNotifications(")]
fixture = r'''
import Foundation

let spotify = "com.spotify.client"
let firefox = "org.mozilla.firefox"
let chrome = "com.google.Chrome"
var clientPIDs: [String: Int32] = [spotify: 11, firefox: 22, chrome: 33]
var activePlayerPaths: [String: AnyObject] = [
    spotify: spotify as NSString, firefox: firefox as NSString, chrome: chrome as NSString
]
var commandQueue: [[String: Any]] = []
var activeCommandID: UUID?
var electedPID: Int32 = 11
var overrideBundle: String?
var electionAllowed = true
var sendError: UInt32 = 0
var sendDelay = 0.01
var results: [[String: Any]] = []
var deliveries: [(String, UInt32)] = []
var polls = 0

let setOverriddenApplication: ((CFString?) -> Int32)? = { bundle in
    overrideBundle = bundle as String?
    if electionAllowed, let bundle = overrideBundle {
        electedPID = clientPIDs[bundle] ?? 0
    }
    return 0
}
func getNowPlayingPID(_ queue: DispatchQueue, _ completion: @escaping (Int32) -> Void) {
    queue.async { completion(electedPID) }
}
func sendCommandToPlayer(_ code: UInt32, _ options: AnyObject?, _ path: AnyObject,
                         _ flags: UInt32, _ queue: DispatchQueue,
                         _ completion: @escaping (UInt32, CFArray?) -> Void) {
    let bundle = path as! String
    precondition(overrideBundle == bundle, "Command lost its target override")
    precondition(electedPID == clientPIDs[bundle], "Command reached the previous player")
    deliveries.append((bundle, code))
    let error = sendError
    queue.asyncAfter(deadline: .now() + sendDelay) { completion(error, nil) }
}
func emitJSON(_ payload: [String: Any]) { results.append(payload) }
func pollAndEmitState() { polls += 1 }
func command(_ action: String, to bundle: String, id: String, seconds: Double? = nil) {
    var payload: [String: Any] = ["action": action, "bundleId": bundle, "requestId": id]
    if let seconds { payload["seconds"] = seconds }
    let data = try! JSONSerialization.data(withJSONObject: payload)
    handleCommandLine(String(decoding: data, as: UTF8.self))
}
func waitForResult(_ count: Int, timeout: TimeInterval = 2.5) {
    let deadline = Date().addingTimeInterval(timeout)
    while results.count < count && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    precondition(results.count == count, "Command did not finish")
}
func reset() {
    precondition(activeCommandID == nil && commandQueue.isEmpty && overrideBundle == nil)
    results.removeAll()
    deliveries.removeAll()
    electedPID = 11
    electionAllowed = true
    sendError = 0
    sendDelay = 0.01
}
'''
checks = r'''
// Firefox receives Play even though Spotify was the elected player.
command("play", to: firefox, id: "firefox-play")
waitForResult(1)
precondition(deliveries.count == 1 && deliveries[0].0 == firefox && deliveries[0].1 == 0)
precondition(results[0]["success"] as? Bool == true && results[0]["requestId"] as? String == "firefox-play")
reset()
print("PASS: rebinds Spotify → Firefox before sending Play")

// Rapid changes cannot replace an override while the preceding command is in flight.
sendDelay = 0.05
command("pause", to: firefox, id: "pause-firefox")
command("play", to: chrome, id: "play-chrome")
waitForResult(2)
precondition(deliveries.map { $0.0 } == [firefox, chrome])
precondition(deliveries.map { $0.1 } == [1, 0])
precondition(results.allSatisfy { $0["success"] as? Bool == true })
reset()
print("PASS: serializes commands when the selected source changes")

// A rejected election must never send to the old player.
electionAllowed = false
command("play", to: firefox, id: "denied-election")
waitForResult(1)
precondition(deliveries.isEmpty && results[0]["success"] as? Bool == false)
reset()
print("PASS: refuses delivery if macOS keeps the previous player elected")

sendError = 7
command("pause", to: firefox, id: "send-failure")
waitForResult(1)
precondition(results[0]["success"] as? Bool == false)
reset()
print("PASS: reports transport errors and releases the override")

command("play", to: "missing.app", id: "missing")
waitForResult(1)
precondition(deliveries.isEmpty && results[0]["success"] as? Bool == false)
reset()
print("PASS: cannot control a missing source")

command("seek", to: firefox, id: "seek-negative", seconds: -5)
waitForResult(1)
precondition(deliveries.count == 1 && deliveries[0].0 == firefox && deliveries[0].1 == 24)
reset()
print("PASS: routes seeking through the selected source")
'''
with tempfile.TemporaryDirectory(prefix="iceland-helper-tests-") as folder:
    script = Path(folder) / "RoutingTests.swift"
    script.write_text(fixture + handlers + checks)
    subprocess.run(
        ["swift", "-module-cache-path", "/tmp/swift-module-cache", str(script)],
        check=True,
        cwd=root,
    )

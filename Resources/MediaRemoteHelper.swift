import Foundation

// MARK: - MediaRemote C Bridge (выполняется внутри системного процесса /usr/bin/swift с полным доступом к mediaremoted)

let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
let playerPathClass = NSClassFromString("MRPlayerPath") as? NSObject.Type
let playerClass = NSClassFromString("MRPlayer") as? NSObject.Type
let queueReqClass = NSClassFromString("MRPlaybackQueueRequest") as? NSObject.Type

let initPlayerPathSel = NSSelectorFromString("initWithOrigin:client:player:")
let defaultPlayerSel = NSSelectorFromString("defaultPlayer")
let defaultQueueReqSel = NSSelectorFromString("defaultPlaybackQueueRequest")
let allocSel = NSSelectorFromString("alloc")

typealias GetOriginFn = @convention(c) () -> AnyObject?
typealias GetClientsFn = @convention(c) (DispatchQueue, @escaping (CFArray?) -> Void) -> Void
typealias GetInfoForPlayerFn = @convention(c) (AnyObject, Bool, DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
typealias GetStateForPlayerFn = @convention(c) (AnyObject, DispatchQueue, @escaping (UInt32) -> Void) -> Void
typealias GetClientBundleIdFn = @convention(c) (AnyObject) -> CFString?
typealias GetClientDisplayNameFn = @convention(c) (AnyObject) -> CFString?
typealias SendCommandToPlayerFn = @convention(c) (UInt32, AnyObject?, AnyObject, UInt32, DispatchQueue, @escaping (UInt32, CFArray?) -> Void) -> Void
typealias ReqQueueForPlayerFn = @convention(c) (AnyObject, AnyObject, DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
typealias GetQueueItemFn = @convention(c) (AnyObject, Int) -> AnyObject?
typealias GetItemArtDataFn = @convention(c) (AnyObject) -> CFData?
typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
typealias InitPlayerPathFn = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> AnyObject

let getLocalOrigin = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetLocalOrigin"), to: GetOriginFn.self)
let getClients = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetNowPlayingClients"), to: GetClientsFn.self)
let getInfoForPlayer = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetNowPlayingInfoForPlayer"), to: GetInfoForPlayerFn.self)
let getStateForPlayer = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetPlaybackStateForPlayer"), to: GetStateForPlayerFn.self)
let getClientBundleId = unsafeBitCast(dlsym(handle, "MRNowPlayingClientGetBundleIdentifier"), to: GetClientBundleIdFn.self)
let getClientDisplayName = unsafeBitCast(dlsym(handle, "MRNowPlayingClientGetDisplayName"), to: GetClientDisplayNameFn.self)
let sendCommandToPlayer = unsafeBitCast(dlsym(handle, "MRMediaRemoteSendCommandToPlayer"), to: SendCommandToPlayerFn.self)
let reqQueueForPlayer = unsafeBitCast(dlsym(handle, "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayerSync"), to: ReqQueueForPlayerFn.self)
let getQueueItem = unsafeBitCast(dlsym(handle, "MRPlaybackQueueGetContentItemAtOffset"), to: GetQueueItemFn.self)
let getItemArtData = unsafeBitCast(dlsym(handle, "MRContentItemGetArtworkData"), to: GetItemArtDataFn.self)
let registerNotifications = unsafeBitCast(dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications"), to: RegisterNotificationsFn.self)

// Без системного entitlement mediaremoted может перенаправить адресную команду
// elected-плееру. На время одной команды явно назначаем приложение-получателя,
// проверяем его PID и снимаем назначение после ответа (либо тайм-аута).
typealias GetNowPlayingPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
let getNowPlayingPID = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID"), to: GetNowPlayingPIDFn.self)
typealias SetOverriddenApplicationFn = @convention(c) (CFString?) -> Int32
let setOverriddenApplication: SetOverriddenApplicationFn? = dlsym(handle, "MRMediaRemoteSetOverriddenNowPlayingApplication").map {
    unsafeBitCast($0, to: SetOverriddenApplicationFn.self)
}

let artworkBgQueue = DispatchQueue(label: "helper.artwork.bg", attributes: .concurrent)
var artworkPathCache: [String: String] = [:]
var attemptedArtworkKeys: Set<String> = []
var activePlayerPaths: [String: AnyObject] = [:]
var clientPIDs: [String: Int32] = [:]
var commandQueue: [[String: Any]] = []
var activeCommandID: UUID?
var stdinBuffer = Data()
var statePollInProgress = false
var statePollRequested = false
var activeStatePollID: UUID?

func clientPID(_ client: AnyObject) -> Int32 {
    guard let obj = client as? NSObject,
          obj.responds(to: NSSelectorFromString("processIdentifier")) else { return 0 }
    return (obj.value(forKey: "processIdentifier") as? NSNumber)?.int32Value ?? 0
}

func makePlayerPath(for client: AnyObject) -> AnyObject? {
    guard let cls = playerPathClass,
          let origin = getLocalOrigin() else { return nil }
    let defaultPlayer = playerClass?.perform(defaultPlayerSel)?.takeUnretainedValue()
    let rawObj = cls.perform(allocSel).takeUnretainedValue()
    guard let imp = rawObj.method(for: initPlayerPathSel) else { return nil }
    let initFn = unsafeBitCast(imp, to: InitPlayerPathFn.self)
    return initFn(rawObj, initPlayerPathSel, origin, client, defaultPlayer)
}

func saveArtworkToTempFile(data: Data, bundleId: String) -> String {
    let safeId = bundleId.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    let filePath = "/tmp/dynamic_island_art_\(safeId).jpg"
    try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    return filePath
}

func pollAndEmitState() {
    guard !statePollInProgress else {
        statePollRequested = true
        return
    }
    statePollInProgress = true
    let pollID = UUID()
    activeStatePollID = pollID
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        guard activeStatePollID == pollID else { return }
        // Потерянный системный callback не должен навсегда остановить опрос.
        activeStatePollID = nil
        statePollInProgress = false
        statePollRequested = false
    }
    getNowPlayingPID(DispatchQueue.main) { electedPID in
        guard activeStatePollID == pollID else { return }
        pollClients(electedPID: electedPID, pollID: pollID)
    }
}

func finishStatePoll(_ payload: [String: Any], pollID: UUID) {
    guard activeStatePollID == pollID else { return }
    activeStatePollID = nil
    emitJSON(payload)
    statePollInProgress = false
    if statePollRequested {
        statePollRequested = false
        DispatchQueue.main.async { pollAndEmitState() }
    }
}

func pollClients(electedPID: Int32, pollID: UUID) {
    getClients(DispatchQueue.main) { cfArray in
        guard activeStatePollID == pollID else { return }
        let clientList = (cfArray as? [AnyObject]) ?? []
        // Не оставляем маршруты закрытых приложений и старые PID.
        activePlayerPaths.removeAll()
        clientPIDs.removeAll()
        if clientList.isEmpty {
            finishStatePoll(["sessions": [], "nowPlayingPID": electedPID], pollID: pollID)
            return
        }
        
        let group = DispatchGroup()
        var sessionsPayload: [[String: Any]] = []
        
        for client in clientList {
            guard let rawBundleId = getClientBundleId(client) as String?,
                  !rawBundleId.isEmpty,
                  let playerPath = makePlayerPath(for: client) else {
                continue
            }
            activePlayerPaths[rawBundleId] = playerPath
            let pid = clientPID(client)
            clientPIDs[rawBundleId] = pid
            let displayName = (getClientDisplayName(client) as String?) ?? ""
            
            group.enter()
            getStateForPlayer(playerPath, DispatchQueue.main) { mrState in
                getInfoForPlayer(playerPath, true, DispatchQueue.main) { info in
                    defer { group.leave() }
                    guard let info else { return }
                    let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !title.isEmpty else { return }
                    
                    let artist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
                    let album = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
                    let rateObj = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double
                    
                    // Состояние берём у конкретного плеера. Звук другого приложения
                    // и системный elected-плеер не определяют состояние этой сессии.
                    let isPlaying = (mrState == 1) && ((rateObj ?? 1.0) > 0.01)
                    
                    let dur = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0.0
                    let rawElapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0.0
                    var currentElapsed = rawElapsed
                    if let ts = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date, isPlaying {
                        let rate = max(rateObj ?? 1.0, 1.0)
                        let delta = max(0, Date().timeIntervalSince(ts)) * rate
                        currentElapsed = dur > 0 ? min(dur, rawElapsed + delta) : (rawElapsed + delta)
                    }
                    
                    let cacheKey = "\(rawBundleId)|\(title)"
                    var artPath = artworkPathCache[cacheKey] ?? ""
                    if artPath.isEmpty,
                       let artData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
                       !artData.isEmpty {
                        artPath = saveArtworkToTempFile(data: artData, bundleId: rawBundleId)
                        artworkPathCache[cacheKey] = artPath
                    } else if artPath.isEmpty && !attemptedArtworkKeys.contains(cacheKey) {
                        attemptedArtworkKeys.insert(cacheKey)
                        artworkBgQueue.async {
                            guard let reqCls = queueReqClass,
                                  let reqObj = reqCls.perform(defaultQueueReqSel)?.takeUnretainedValue() as? NSObject else { return }
                            reqObj.setValue(600.0, forKey: "artworkWidth")
                            reqObj.setValue(600.0, forKey: "artworkHeight")
                            reqQueueForPlayer(reqObj, playerPath, artworkBgQueue) { pbQueue in
                                if let pbQueue,
                                   let item = getQueueItem(pbQueue, 0),
                                   let data = getItemArtData(item) as Data?,
                                   !data.isEmpty {
                                    let savedPath = saveArtworkToTempFile(data: data, bundleId: rawBundleId)
                                    DispatchQueue.main.async {
                                        artworkPathCache[cacheKey] = savedPath
                                        pollAndEmitState()
                                    }
                                }
                            }
                        }
                    }
                    
                    sessionsPayload.append([
                        "bundleId": rawBundleId,
                        "displayName": displayName,
                        "title": title,
                        "artist": artist,
                        "album": album,
                        "duration": dur,
                        "elapsed": currentElapsed,
                        "isPlaying": isPlaying,
                        "mrState": mrState,
                        "pid": pid,
                        "isElected": pid != 0 && pid == electedPID,
                        "artworkPath": artPath
                    ])
                }
            }
        }
        
        group.notify(queue: .main) {
            finishStatePoll(["sessions": sessionsPayload, "nowPlayingPID": electedPID], pollID: pollID)
        }
    }
}

func emitJSON(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let line = String(data: data, encoding: .utf8) else { return }
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

func commandCode(for action: String) -> UInt32? {
    switch action {
    case "play": return 0
    case "pause": return 1
    case "toggle": return 2
    case "next": return 4
    case "previous": return 5
    case "seek": return 24
    default: return nil
    }
}

func handleCommandLine(_ line: String) {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let action = json["action"] as? String else { return }
    
    if action == "poll" {
        pollAndEmitState()
        return
    }
    
    commandQueue.append(json)
    processNextCommand()
}

func processNextCommand() {
    guard activeCommandID == nil, !commandQueue.isEmpty else { return }
    let json = commandQueue.removeFirst()
    let commandID = UUID()
    activeCommandID = commandID

    func finish(success: Bool, message: String? = nil) {
        // Поздние ответы после тайм-аута не должны снимать назначение новой команды.
        guard activeCommandID == commandID else { return }
        _ = setOverriddenApplication?(nil)
        var result: [String: Any] = [
            "event": "commandResult",
            "requestId": json["requestId"] as? String ?? "",
            "bundleId": json["bundleId"] as? String ?? "",
            "action": json["action"] as? String ?? "",
            "success": success
        ]
        if let message { result["message"] = message }
        emitJSON(result)
        activeCommandID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pollAndEmitState() }
        processNextCommand()
    }

    guard let bundleId = json["bundleId"] as? String,
          let action = json["action"] as? String,
          let code = commandCode(for: action),
          let playerPath = activePlayerPaths[bundleId],
          let targetPID = clientPIDs[bundleId], targetPID > 0 else {
        finish(success: false, message: "The selected source is no longer available.")
        return
    }

    var options: NSDictionary?
    if action == "seek" {
        guard let seconds = json["seconds"] as? Double, seconds.isFinite else {
            finish(success: false, message: "Invalid playback position.")
            return
        }
        options = ["kMRMediaRemoteOptionPlaybackPosition": NSNumber(value: max(0, seconds))]
    }

    // Для адресного управления браузером требуется именно override bundle ID;
    // OverrideEnabled(true) назначил бы сам helper, а не выбранный браузер.
    _ = setOverriddenApplication?(bundleId as CFString)
    let electionDeadline = Date().addingTimeInterval(1.5)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        finish(success: false, message: "The source did not respond to the playback command.")
    }

    func sendWhenTargetIsElected() {
        guard activeCommandID == commandID else { return }
        getNowPlayingPID(DispatchQueue.main) { electedPID in
            guard activeCommandID == commandID else { return }
            guard clientPIDs[bundleId] == targetPID else {
                finish(success: false, message: "The selected source is no longer available.")
                return
            }
            guard electedPID == targetPID else {
                if setOverriddenApplication != nil, Date() < electionDeadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { sendWhenTargetIsElected() }
                } else {
                    finish(success: false, message: "macOS did not allow control of the selected source.")
                }
                return
            }
            // Здесь нет глобального fallback: при несовпадении получателя команда
            // никогда не отправляется предыдущему приложению.
            sendCommandToPlayer(code, options, playerPath, 0, DispatchQueue.main) { error, statuses in
                let handlerStatuses = (statuses as? [NSNumber]) ?? []
                let success = error == 0 && handlerStatuses.allSatisfy { $0.intValue == 0 }
                finish(success: success, message: success ? nil : "The selected app could not complete the command.")
            }
        }
    }
    sendWhenTargetIsElected()
}

registerNotifications(DispatchQueue.main)
let nc = NotificationCenter.default
for name in [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
] {
    nc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in
        pollAndEmitState()
    }
}

FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    DispatchQueue.main.async {
        guard !data.isEmpty else {
            _ = setOverriddenApplication?(nil)
            exit(0)
        }
        // Pipe не гарантирует границы JSON-строк или UTF-8 символов.
        stdinBuffer.append(data)
        while let newline = stdinBuffer.firstIndex(of: 0x0A) {
            let lineData = stdinBuffer[..<newline]
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                handleCommandLine(line)
            }
            stdinBuffer.removeSubrange(...newline)
        }
    }
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    if getppid() <= 1 {
        _ = setOverriddenApplication?(nil)
        exit(0)
    }
    pollAndEmitState()
}

pollAndEmitState()
RunLoop.main.run()

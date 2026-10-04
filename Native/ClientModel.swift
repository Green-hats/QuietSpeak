import AVFoundation
import AppKit
import SwiftUI

@_silgen_name("qs_initialize") private func coreInitialize()
@_silgen_name("qs_command") private func coreCommand(_ json: UnsafePointer<CChar>)
@_silgen_name("qs_poll") private func corePoll() -> UnsafeMutablePointer<CChar>
@_silgen_name("qs_free_string") private func coreFree(_ pointer: UnsafeMutablePointer<CChar>)

enum ConnectionStatus {
    case offline, connecting, connected, reconnecting
    var label: String {
        switch self {
        case .offline: "未连接"
        case .connecting: "正在连接"
        case .connected: "已连接"
        case .reconnecting: "正在重连"
        }
    }
}
enum TalkMode: String, CaseIterable, Identifiable {
    case pushToTalk = "按键说话"
    case openMic = "持续说话"
    var id: String { rawValue }
}

@MainActor final class ClientModel: ObservableObject {
    @Published var bookmarks: [ServerBookmark]
    @Published var selectedBookmark: UUID?
    @Published var activeBookmark: UUID?
    @Published var status: ConnectionStatus = .offline
    @Published var statusDetail = "选择服务器，开始交流"
    @Published var serverName = "轻语"
    @Published var channels: [Channel] = []
    @Published var members: [Member] = []
    @Published var messages: [ChatMessage] = []
    @Published var ownID: UInt16 = 0
    @Published var currentChannel: UInt64 = 0
    @Published var selectedChannel: UInt64?
    @Published var microphoneEnabled = false
    @Published var deafened = false
    @Published var holding = false
    @Published var canSendAudio = false
    @Published var talkMode: TalkMode = .pushToTalk
    @Published var volume: Double = 1
    @Published var speaking: Set<UInt16> = []
    @Published var showConnection = false
    @Published var showSettings = false
    @Published var error: String?
    @Published var audioWarning: String?
    @Published var outputDevice = "系统默认输出设备"
    @Published var testingSpeakers = false
    @Published var search = ""
    private var speakerTimes: [UInt16: Date] = [:]
    private var timer: Timer?
    private var eventMonitor: Any?
    private var inactiveObserver: NSObjectProtocol?
    private var permissionRequest = UUID()
    private var lastAudio: String?
    private var welcomed = false
    private var followJoinedChannel = true

    init() {
        if let data = UserDefaults.standard.data(forKey: "bookmarks"),
            let saved = try? JSONDecoder().decode([ServerBookmark].self, from: data)
        {
            bookmarks = saved
        } else {
            bookmarks = []
        }
        selectedBookmark = bookmarks.first?.id
        coreInitialize()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            MainActor.assumeIsolated {
                self?.setHolding(event.modifierFlags.contains(.option))
            }
            return event
        }
        inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setHolding(false) }
        }
    }
    var selectedServer: ServerBookmark? { bookmarks.first { $0.id == selectedBookmark } }
    var busy: Bool { status != .offline }
    var connected: Bool { status == .connected }
    var selected: Channel? { channels.first { $0.id == selectedChannel } }
    var joined: Channel? { channels.first { $0.id == currentChannel } }
    var microphoneRequested: Bool {
        connected && microphoneEnabled && !deafened && (talkMode == .openMic || holding)
    }
    var transmitting: Bool { microphoneRequested && canSendAudio }
    var canChat: Bool { connected && selectedChannel == currentChannel }
    var visibleMessages: [ChatMessage] {
        messages.filter { $0.scope != "channel" || $0.channel == selectedChannel }
    }
    var visibleMembers: [Member] {
        members.filter { $0.channel == selectedChannel }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "bookmarks")
        }
    }
    func saveBookmark(
        id: UUID?, name: String, address: String, nickname: String, password: String,
        rememberPassword: Bool
    ) throws -> ServerBookmark {
        let address = try ConnectionAddress.normalize(address)
        let nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty, nickname.count <= 30, nickname.utf8.count <= 64 else {
            throw InputError("昵称需要为 1–30 个字符，且不超过 64 字节")
        }
        let item = ServerBookmark(
            id: id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? address : name,
            address: address, nickname: nickname)
        if let index = bookmarks.firstIndex(where: { $0.id == item.id }) {
            bookmarks[index] = item
        } else {
            bookmarks.append(item)
        }
        selectedBookmark = item.id
        saveBookmarks()
        if !SecureStore.save(rememberPassword ? password : "", account: "password-\(item.id)") {
            throw InputError("钥匙串无法保存密码；服务器收藏已保存")
        }
        return item
    }
    func removeBookmark(_ item: ServerBookmark) {
        bookmarks.removeAll { $0.id == item.id }
        _ = SecureStore.save("", account: "password-\(item.id)")
        if selectedBookmark == item.id { selectedBookmark = bookmarks.first?.id }
        saveBookmarks()
    }
    func connect(_ item: ServerBookmark, password: String = "") {
        guard !busy else { return }
        do {
            let address = try ConnectionAddress.normalize(item.address)
            channels = []
            members = []
            messages = []
            speaking = []
            currentChannel = 0
            selectedChannel = nil
            microphoneEnabled = false
            holding = false
            deafened = false
            audioWarning = nil
            error = nil
            welcomed = false
            lastAudio = nil
            status = .connecting
            statusDetail = "正在连接 \(item.address)…"
            activeBookmark = item.id
            selectedBookmark = item.id
            send([
                "op": "connect", "address": address, "nickname": item.nickname,
                "password": password,
                "identity": SecureStore.read("identity") ?? "",
            ])
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        permissionRequest = UUID()
        microphoneEnabled = false
        holding = false
        updateAudio()
        send(["op": "disconnect"])
        statusDetail = "正在断开连接…"
    }
    func joinSelected(password: String = "") {
        guard connected, let selectedChannel, selectedChannel != currentChannel else { return }
        followJoinedChannel = true
        send(["op": "join", "channel": selectedChannel, "password": password])
    }
    func sendChat(_ text: String) {
        guard canChat else { return }
        send(["op": "chat", "text": text])
    }
    func toggleMicrophone() {
        if microphoneEnabled {
            permissionRequest = UUID()
            microphoneEnabled = false
            holding = false
            updateAudio()
            return
        }
        guard connected else { return }
        let request = UUID()
        permissionRequest = request
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneEnabled = true
            deafened = false
            updateAudio()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.permissionRequest == request, self.connected else {
                        return
                    }
                    if granted {
                        self.microphoneEnabled = true
                        self.deafened = false
                        self.updateAudio()
                    } else {
                        self.audioWarning = "麦克风权限未开启。可在系统设置 → 隐私与安全性 → 麦克风中允许轻语。"
                    }
                }
            }
        default: audioWarning = "麦克风权限未开启。可在系统设置 → 隐私与安全性 → 麦克风中允许轻语。"
        }
    }
    func toggleDeafen() {
        deafened.toggle()
        holding = false
        updateAudio()
    }
    func testSpeakers() {
        guard !testingSpeakers else { return }
        guard volume > 0 else {
            audioWarning = "请先提高播放音量，再测试扬声器。"
            return
        }
        audioWarning = nil
        testingSpeakers = true
        send(["op": "testOutput", "volume": volume])
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            testingSpeakers = false
        }
    }
    func setHolding(_ value: Bool) {
        guard talkMode == .pushToTalk else { return }
        let next = value && microphoneEnabled && connected && NSApp.isActive
        if holding != next {
            holding = next
            updateAudio()
        }
    }
    func updateAudio() {
        let payload: [String: Any] = [
            "op": "audio", "microphone": microphoneRequested, "deafened": deafened,
            "volume": volume,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys),
            let string = String(data: data, encoding: .utf8), string != lastAudio
        else { return }
        lastAudio = string
        string.withCString { coreCommand($0) }
    }
    func shutdown() {
        microphoneEnabled = false
        holding = false
        updateAudio()
        send(["op": "disconnect"])
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
        timer?.invalidate()
    }
    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return }
        json.withCString { coreCommand($0) }
    }
    private func poll() {
        let pointer = corePoll()
        let data = Data(String(cString: pointer).utf8)
        coreFree(pointer)
        if let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for event in events { accept(event) }
        }
        let now = Date()
        speakerTimes = speakerTimes.filter { now.timeIntervalSince($0.value) < 0.45 }
        let active = Set(speakerTimes.keys)
        if active != speaking { speaking = active }
    }
    private func accept(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "identity":
            if let value = event["value"] as? String, !SecureStore.save(value, account: "identity")
            {
                error = "身份未能保存到钥匙串，请允许轻语访问钥匙串后再连接。"
                disconnect()
            }
        case "connected":
            status = .connected
            statusDetail = "连接成功"
            updateAudio()
        case "reconnecting":
            status = .reconnecting
            statusDetail = "连接中断，正在尝试重连…"
            microphoneEnabled = false
            holding = false
            lastAudio = nil
            members = []
            channels = []
            speaking = []
            speakerTimes = [:]
        case "disconnected":
            status = .offline
            statusDetail = "已断开连接"
            microphoneEnabled = false
            holding = false
            canSendAudio = false
            activeBookmark = nil
            members = []
            channels = []
            currentChannel = 0
            selectedChannel = nil
            speaking = []
            speakerTimes = [:]
        case "snapshot":
            guard let data = try? JSONSerialization.data(withJSONObject: event),
                let s = try? JSONDecoder().decode(Snapshot.self, from: data)
            else { return }
            let changed = currentChannel != s.currentChannel
            serverName = s.server
            ownID = s.own
            currentChannel = s.currentChannel
            channels = s.channels
            members = s.clients
            if changed {
                // Moving channels resets a held key and active capture.
                holding = false
                if microphoneEnabled {
                    microphoneEnabled = false
                    updateAudio()
                }
            }
            if selectedChannel == nil || followJoinedChannel && changed
                || !channels.contains(where: { $0.id == selectedChannel })
            {
                selectedChannel = currentChannel
                followJoinedChannel = false
            }
            if !welcomed {
                welcomed = true
                if !s.welcome.isEmpty {
                    messages.append(
                        ChatMessage(
                            sender: "服务器", text: s.welcome, channel: 0, scope: "system",
                            outgoing: false))
                }
            }
        case "chat":
            guard let text = event["text"] as? String, let sender = event["sender"] as? String
            else { return }
            messages.append(
                ChatMessage(
                    sender: sender, text: text,
                    channel: (event["channel"] as? NSNumber)?.uint64Value ?? 0,
                    scope: event["scope"] as? String ?? "channel",
                    outgoing: event["outgoing"] as? Bool ?? false))
            if messages.count > 500 { messages.removeFirst(messages.count - 500) }
        case "talkPermission": canSendAudio = event["allowed"] as? Bool ?? false
        case "speaking":
            if let id = (event["client"] as? NSNumber)?.uint16Value { speakerTimes[id] = Date() }
        case "status": statusDetail = event["message"] as? String ?? statusDetail
        case "audioError":
            audioWarning = event["message"] as? String
            if event["capture"] as? Bool == true {
                microphoneEnabled = false
                holding = false
                updateAudio()
            }
        case "audioDevice": outputDevice = event["name"] as? String ?? "系统默认输出设备"
        case "error", "fatal": error = event["message"] as? String ?? "发生未知错误"
        default: break
        }
    }
}

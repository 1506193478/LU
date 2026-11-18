import Foundation
import Network
import Combine

// MARK: - 协议

/// 一起看的消息。刻意用扁平结构：字段都可选，服务端与客户端共用同一套编解码。
struct SyncPlayMessage: Codable {
    var type: String              // hello / welcome / state / play / pause / seek / episode / chat
    var position: Double?
    var paused: Bool?
    var episodeKey: String?
    var name: String?
    var text: String?
    var code: String?
    var members: Int?
    var timestamp: Double?
}

// MARK: - 服务端

/// 局域网「一起看」服务端。
///
/// Network.framework 的 `NWProtocolWebSocket` 同时负责握手与帧封装，
/// 收到的是完整消息（无需自己处理分片）。房间状态以房主为准：
/// 任何客户端上报 play/pause/seek，服务端更新权威状态后广播给所有人。
final class SyncPlayServer: ObservableObject {
    static let shared = SyncPlayServer()

    @Published private(set) var isRunning = false
    @Published private(set) var memberCount = 0
    @Published private(set) var code = ""
    @Published private(set) var lastError: String?

    private final class Peer {
        let id = UUID()
        let connection: NWConnection
        var name = "访客"
        init(connection: NWConnection) { self.connection = connection }
    }

    private let queue = DispatchQueue(label: "lu.sync.server")
    private var listener: NWListener?
    private var peers: [UUID: Peer] = [:]

    /// 观众操作被采纳时回调（房主本地播放器要跟着动）
    var onRemoteAction: ((SyncPlayMessage) -> Void)?
    /// 收到观众聊天
    var onChat: ((String, String) -> Void)?

    private var port: UInt16 = 9301
    private var position: Double = 0
    private var paused = true
    private var episodeKey = ""
    private var updatedAt = Date()

    /// 同网段的人手输这个地址就能加入
    var localAddresses: [String] {
        LuNetworkInfo.localIPv4().map { "\($0):\(port)" }
    }

    private init() {}

    func start(port: UInt16 = 9301) {
        stop()
        code = Self.makeCode()
        self.port = port
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        do {
            let listener = try NWListener(using: parameters, on: endpointPort)
            listener.service = NWListener.Service(name: "LU-\(code)", type: "_lu-sync._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed(let error):
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            luLogInfo("SyncPlay", "服务端已启动，房间 \(code)")
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            luLogError("SyncPlay", "服务端启动失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.peers.values.forEach { $0.connection.cancel() }
            self.peers.removeAll()
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.memberCount = 0
        }
    }

    /// 房主把自己的播放状态推给所有人（切集时也调用）。
    func publish(position: Double, paused: Bool, episodeKey: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.position = position
            self.paused = paused
            self.episodeKey = episodeKey
            self.updatedAt = Date()
            self.broadcastState()
        }
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        let peer = Peer(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.peers[peer.id] = peer
                self.receive(peer)
                DispatchQueue.main.async { self.memberCount = self.peers.count }
            case .failed, .cancelled:
                self.drop(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func drop(_ peer: Peer) {
        peers[peer.id] = nil
        peer.connection.cancel()
        DispatchQueue.main.async { self.memberCount = self.peers.count }
        broadcastState()
    }

    private func receive(_ peer: Peer) {
        peer.connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty,
               let message = try? JSONDecoder().decode(SyncPlayMessage.self, from: data) {
                self.handle(message, from: peer)
            }
            if error == nil {
                self.receive(peer)
            } else {
                self.drop(peer)
            }
        }
    }

    private func send(_ message: SyncPlayMessage, to peer: Peer) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data, to: peer)
    }

    private func send(_ data: Data, to peer: Peer) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        peer.connection.send(content: data, contentContext: context, isComplete: true,
                             completion: .contentProcessed { _ in })
    }

    private func broadcast(_ message: SyncPlayMessage, excluding excluded: Peer? = nil) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        for peer in peers.values where peer.id != excluded?.id { send(data, to: peer) }
    }

    /// 房主发言：转给所有观众
    func broadcastChat(name: String, text: String) {
        queue.async { [weak self] in
            self?.broadcast(SyncPlayMessage(type: "chat", name: name, text: text))
        }
    }

    private func notifyRemote(_ message: SyncPlayMessage) {
        DispatchQueue.main.async { [weak self] in self?.onRemoteAction?(message) }
    }

    private func broadcastState() {
        broadcast(stateMessage())
    }

    private func stateMessage() -> SyncPlayMessage {
        var current = position
        if !paused {
            current += Date().timeIntervalSince(updatedAt)
        }
        return SyncPlayMessage(type: "state",
                               position: current,
                               paused: paused,
                               episodeKey: episodeKey,
                               members: peers.count,
                               code: code,
                               timestamp: Date().timeIntervalSince1970)
    }

    // MARK: 消息

    private func handle(_ message: SyncPlayMessage, from peer: Peer) {
        switch message.type {
        case "hello":
            peer.name = message.name ?? "访客"
            send(SyncPlayMessage(type: "welcome", code: code, members: peers.count), to: peer)
            send(stateMessage(), to: peer)
            broadcastState()
            luLogInfo("SyncPlay", "\(peer.name) 加入房间")
        case "play":
            paused = false
            if let value = message.position { position = value }
            updatedAt = Date()
            broadcastState()
            notifyRemote(message)
        case "pause":
            if let value = message.position { position = value }
            paused = true
            updatedAt = Date()
            broadcastState()
            notifyRemote(message)
        case "seek":
            if let value = message.position { position = value }
            updatedAt = Date()
            broadcastState()
            notifyRemote(message)
        case "episode":
            episodeKey = message.episodeKey ?? ""
            position = 0
            paused = true
            updatedAt = Date()
            broadcastState()
            notifyRemote(message)
        case "chat":
            let name = message.name ?? peer.name
            let text = message.text ?? ""
            broadcast(message, excluding: peer)
            DispatchQueue.main.async { [weak self] in self?.onChat?(name, text) }
        default:
            break
        }
    }

    private static func makeCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).compactMap { _ in letters.randomElement() })
    }
}

// MARK: - 客户端

struct SyncPlayHost: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

final class SyncPlayClient: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "未连接"
            case .connecting: return "连接中…"
            case .connected: return "已连接"
            case .failed(let reason): return "连接失败：\(reason)"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var members = 0
    @Published private(set) var roomCode = ""
    @Published private(set) var lastState: SyncPlayMessage?
    @Published private(set) var chats: [String] = []

    var onState: ((SyncPlayMessage) -> Void)?
    var onChat: ((String, String) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "lu.sync.client")

    func connect(host: String, port: UInt16, name: String) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let target = NWEndpoint.Host(host)
        connect(endpoint: .hostPort(host: target, port: endpointPort), name: name)
    }

    /// 支持 `192.168.1.8:9301`、`ws://host:port` 两种写法。
    func connect(address: String, name: String) {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: "ws://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
        let pieces = raw.split(separator: ":")
        let host = pieces.first.map(String.init) ?? raw
        let port = pieces.count > 1 ? (UInt16(pieces[1]) ?? 9301) : 9301
        connect(host: host, port: port, name: name)
    }

    func connect(endpoint: NWEndpoint, name: String) {
        disconnect()

        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        status = .connecting

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.status = .connected
                    self.send(SyncPlayMessage(type: "hello", name: name))
                case .failed(let error):
                    self.status = .failed(error.localizedDescription)
                case .cancelled:
                    if self.status != .idle { self.status = .idle }
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
        luLogInfo("SyncPlay", "尝试连接 \(endpoint)")
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        status = .idle
        members = 0
    }

    func send(_ message: SyncPlayMessage) {
        guard let connection, let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty,
               let message = try? JSONDecoder().decode(SyncPlayMessage.self, from: data) {
                DispatchQueue.main.async {
                    self.handle(message)
                }
            }
            if error == nil {
                self.receive(on: connection)
            } else {
                DispatchQueue.main.async {
                    if case .failed = self.status { return }
                    self.status = .failed(error?.localizedDescription ?? "连接中断")
                }
            }
        }
    }

    private func handle(_ message: SyncPlayMessage) {
        switch message.type {
        case "welcome":
            roomCode = message.code ?? ""
            members = message.members ?? 0
        case "state":
            members = message.members ?? members
            if let code = message.code { roomCode = code }
            lastState = message
            onState?(message)
        case "chat":
            if let text = message.text {
                chats.append(text)
                onChat?(message.name ?? "对方", text)
            }
        default:
            break
        }
    }
}

// MARK: - Bonjour 浏览

final class SyncPlayBrowser: ObservableObject {
    @Published private(set) var hosts: [SyncPlayHost] = []
    private var browser: NWBrowser?

    func start() {
        stop()
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let browser = NWBrowser(for: .bonjour(type: "_lu-sync._tcp", domain: nil),
                                using: parameters)
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                luLogWarn("SyncPlay", "浏览器失败：\(error.localizedDescription)")
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let hosts = results.map { result -> SyncPlayHost in
                let name = result.endpoint.debugDescription
                return SyncPlayHost(id: "\(result.endpoint)", name: name, endpoint: result.endpoint)
            }
            DispatchQueue.main.async { self.hosts = hosts }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

// MARK: - 会话（播放器侧统一入口）

struct SyncPlayChat: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var text: String
    var isMine: Bool
    var at = Date()
}

/// 播放器只跟这个单例打交道。
///
/// 两套通道：
/// - `.lan`：本机起 `NWListener`（Bonjour 广播 + IP 直连），只同一 Wi-Fi 可用；
/// - `.relay`：双方连公网 WebSocket 中继，靠房间码配对，跨网络可用。
///
/// 房主权威：观众的操作先到房主，房主应用到本地播放器后再把状态广播出去。
final class SyncPlaySession: ObservableObject {
    static let shared = SyncPlaySession()

    enum Role: Equatable {
        case none
        case host
        case guest

        var title: String {
            switch self {
            case .none: return "未开启"
            case .host: return "房主"
            case .guest: return "观众"
            }
        }
    }

    enum Mode: Equatable {
        case lan
        case relay

        var title: String { self == .lan ? "局域网" : "跨网中继" }
    }

    @Published private(set) var role: Role = .none
    @Published private(set) var mode: Mode = .lan
    @Published private(set) var roomCode = ""
    @Published private(set) var statusText = "未连接"
    @Published private(set) var members = 0
    @Published private(set) var messages: [SyncPlayChat] = []

    var applyRemote: ((SyncPlayMessage) -> Void)?
    /// 房主定时上报时用来取当前位置
    var positionProvider: (() -> Double)?

    private let server = SyncPlayServer.shared
    private let client = SyncPlayClient()
    private let relay = SyncPlayRelay()
    private var heartbeat: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastPaused = false
    private var lastEpisodeKey = ""
    private var lastPosition: Double = 0

    private init() {
        // 局域网 · 观众侧
        client.onState = { [weak self] message in
            guard let self, self.role == .guest, self.mode == .lan else { return }
            self.members = message.members ?? self.members
            self.applyRemote?(message)
        }
        client.onChat = { [weak self] name, text in
            self?.append(name: name, text: text, mine: false)
        }
        client.$members.receive(on: RunLoop.main).sink { [weak self] value in
            guard let self, self.role == .guest, self.mode == .lan else { return }
            self.members = value
        }.store(in: &cancellables)
        client.$status.receive(on: RunLoop.main).sink { [weak self] status in
            guard let self, self.role == .guest, self.mode == .lan else { return }
            self.statusText = status.text
        }.store(in: &cancellables)

        // 局域网 · 房主侧：观众的操作要落到本机播放器
        server.onChat = { [weak self] name, text in
            self?.append(name: name, text: text, mine: false)
        }
        server.onRemoteAction = { [weak self] message in
            guard let self, self.role == .host, self.mode == .lan else { return }
            self.rememberRemote(message)
            self.applyRemote?(message)
        }

        // 中继
        relay.onMessage = { [weak self] message in
            guard let self else { return }
            switch message.type {
            case "state":
                self.members = message.members ?? self.members
                if let code = message.code, !code.isEmpty { self.roomCode = code }
                if self.role == .guest { self.applyRemote?(message) }
            case "chat":
                self.append(name: message.name ?? "对方", text: message.text ?? "", mine: false)
            case "play", "pause", "seek", "episode":
                guard self.role == .host else { return }
                self.rememberRemote(message)
                self.applyRemote?(message)
                self.relay.send(self.stateMessage(position: self.lastPosition))
            default:
                break
            }
        }
        relay.onClosed = { [weak self] reason in
            guard let self, self.role != .none else { return }
            self.statusText = reason
            self.members = 0
        }
        relay.$code.receive(on: RunLoop.main).sink { [weak self] value in
            guard let self, self.mode == .relay, !value.isEmpty else { return }
            self.roomCode = value
        }.store(in: &cancellables)
        relay.$state.receive(on: RunLoop.main).sink { [weak self] state in
            guard let self, self.mode == .relay else { return }
            self.statusText = state.text
        }.store(in: &cancellables)
        relay.$members.receive(on: RunLoop.main).sink { [weak self] value in
            guard let self, self.mode == .relay else { return }
            self.members = max(value, self.role == .none ? 0 : 1)
        }.store(in: &cancellables)
    }

    // MARK: 开房 / 加入

    /// `relayURL` 为空 → 局域网；填了 → 走公网中继。
    func startHosting(relayURL: String = "") {
        resetRoom()
        if let url = Self.relayURL(from: relayURL) {
            mode = .relay
            role = .host
            statusText = "连接中继…"
            relay.create(relay: url, name: AppSettings.shared.syncPlayName)
        } else {
            mode = .lan
            role = .host
            server.start()
            roomCode = server.code
            members = 1
            statusText = "房间已开启"
        }
        startHeartbeat()
        luLogInfo("SyncPlay", "开房（\(mode.title)）")
    }

    func join(address: String, name: String) {
        resetRoom()
        mode = .lan
        role = .guest
        statusText = "连接中…"
        client.connect(address: address, name: name)
        startHeartbeat()
    }

    func join(endpoint: NWEndpoint, name: String) {
        resetRoom()
        mode = .lan
        role = .guest
        statusText = "连接中…"
        client.connect(endpoint: endpoint, name: name)
        startHeartbeat()
    }

    /// 跨网络：中继地址 + 房间码
    func join(relayURL: String, code: String, name: String) {
        guard let url = Self.relayURL(from: relayURL) else {
            statusText = "中继地址无效"
            return
        }
        resetRoom()
        mode = .relay
        role = .guest
        statusText = "连接中继…"
        relay.join(relay: url, code: code.uppercased(), name: name)
        startHeartbeat()
        luLogInfo("SyncPlay", "加入中继房间 \(code)")
    }

    func leave() {
        resetRoom()
        role = .none
        mode = .lan
        statusText = "未连接"
        luLogInfo("SyncPlay", "已离开房间")
    }

    private func resetRoom() {
        heartbeat?.invalidate()
        heartbeat = nil
        server.stop()
        client.disconnect()
        relay.close()
        roomCode = ""
        members = 0
        messages.removeAll()
    }

    /// `host:8443` / `wss://host/path` / `https://host` 都接受
    static func relayURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("https://") {
            text = "wss://" + String(text.dropFirst("https://".count))
        } else if text.hasPrefix("http://") {
            text = "ws://" + String(text.dropFirst("http://".count))
        } else if !text.hasPrefix("ws://") && !text.hasPrefix("wss://") {
            text = "wss://" + text
        }
        return URL(string: text)
    }

    /// 房主地址提示（局域网模式用）
    var lanAddresses: [String] { mode == .lan ? server.localAddresses : [] }

    // MARK: 上报

    func pushPlay(position: Double, episodeKey: String) {
        remember(position: position, paused: false, episode: episodeKey)
        switch (mode, role) {
        case (.lan, .host):
            server.publish(position: position, paused: false, episodeKey: episodeKey)
        case (.lan, .guest):
            client.send(actionMessage("play", position: position, paused: false, episodeKey: episodeKey))
        case (.relay, .host):
            relay.send(stateMessage(position: position))
        case (.relay, .guest):
            relay.send(actionMessage("play", position: position, paused: false, episodeKey: episodeKey))
        case (_, .none):
            break
        }
    }

    func pushPause(position: Double, episodeKey: String) {
        remember(position: position, paused: true, episode: episodeKey)
        switch (mode, role) {
        case (.lan, .host):
            server.publish(position: position, paused: true, episodeKey: episodeKey)
        case (.lan, .guest):
            client.send(actionMessage("pause", position: position, paused: true, episodeKey: episodeKey))
        case (.relay, .host):
            relay.send(stateMessage(position: position))
        case (.relay, .guest):
            relay.send(actionMessage("pause", position: position, paused: true, episodeKey: episodeKey))
        case (_, .none):
            break
        }
    }

    func pushSeek(position: Double, paused: Bool, episodeKey: String) {
        remember(position: position, paused: paused, episode: episodeKey)
        switch (mode, role) {
        case (.lan, .host):
            server.publish(position: position, paused: paused, episodeKey: episodeKey)
        case (.lan, .guest):
            client.send(actionMessage("seek", position: position, paused: paused, episodeKey: episodeKey))
        case (.relay, .host):
            relay.send(stateMessage(position: position))
        case (.relay, .guest):
            relay.send(actionMessage("seek", position: position, paused: paused, episodeKey: episodeKey))
        case (_, .none):
            break
        }
    }

    func pushEpisode(_ key: String) {
        remember(position: 0, paused: true, episode: key)
        switch (mode, role) {
        case (.lan, .host):
            server.publish(position: 0, paused: true, episodeKey: key)
        case (.lan, .guest):
            client.send(actionMessage("episode", position: 0, paused: true, episodeKey: key))
        case (.relay, .host):
            relay.send(stateMessage(position: 0))
        case (.relay, .guest):
            relay.send(actionMessage("episode", position: 0, paused: true, episodeKey: key))
        case (_, .none):
            break
        }
    }

    // MARK: 聊天

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, role != .none else { return }
        let name = AppSettings.shared.syncPlayName
        append(name: name, text: trimmed, mine: true)
        let message = SyncPlayMessage(type: "chat", name: name, text: trimmed)
        switch (mode, role) {
        case (.lan, .host):
            server.broadcastChat(name: name, text: trimmed)
        case (.lan, .guest):
            client.send(message)
        case (.relay, _):
            relay.send(message)
        case (_, .none):
            break
        }
    }

    private func append(name: String, text: String, mine: Bool) {
        guard !text.isEmpty else { return }
        messages.append(SyncPlayChat(name: name, text: text, isMine: mine))
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    }

    // MARK: 内部

    private func actionMessage(_ type: String, position: Double, paused: Bool,
                               episodeKey: String) -> SyncPlayMessage {
        SyncPlayMessage(type: type, position: position, paused: paused,
                        episodeKey: episodeKey, name: AppSettings.shared.syncPlayName)
    }

    private func stateMessage(position: Double) -> SyncPlayMessage {
        SyncPlayMessage(type: "state", position: position, paused: lastPaused,
                        episodeKey: lastEpisodeKey, members: max(relay.members, 1),
                        code: roomCode, timestamp: Date().timeIntervalSince1970)
    }

    private func rememberRemote(_ message: SyncPlayMessage) {
        if let paused = message.paused { lastPaused = paused }
        if let position = message.position { lastPosition = position }
        if let key = message.episodeKey, !key.isEmpty { lastEpisodeKey = key }
    }

    private func remember(position: Double, paused: Bool, episode: String) {
        lastPosition = position
        lastPaused = paused
        lastEpisodeKey = episode
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, self.role == .host else { return }
            let position = self.positionProvider?() ?? self.lastPosition
            switch self.mode {
            case .lan:
                self.server.publish(position: position,
                                    paused: self.lastPaused,
                                    episodeKey: self.lastEpisodeKey)
            case .relay:
                self.relay.send(self.stateMessage(position: position))
            }
        }
    }
}

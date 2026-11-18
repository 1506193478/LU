import Foundation
import Combine
import Darwin

// MARK: - 中继客户端

/// 跨网络「一起看」。
///
/// 局域网模式（Bonjour / IP 直连）只能同一 Wi-Fi；出了家门就没法互通。
/// 这里补一条公网通道：双方各自连一台中转服务器（`server/lu-sync-relay.ts`），
/// 房主 `create` 拿房间码，观众用房间码 `join`，之后消息由中继原样转发。
/// 中继只做转发，不存任何播放数据，也不做鉴权之外的记录。
final class SyncPlayRelay: ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        case ready
        case failed(String)

        var text: String {
            switch self {
            case .idle: return "未连接"
            case .connecting: return "连接中…"
            case .ready: return "已连接"
            case .failed(let reason): return "连接失败：\(reason)"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var code = ""
    @Published private(set) var members = 0
    @Published private(set) var isHost = false

    /// 收到 `state` / `chat` 等业务消息
    var onMessage: ((SyncPlayMessage) -> Void)?
    /// 对端（房主或中继）断开
    var onClosed: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private var pendingCreate = false
    private var pendingJoinCode: String?
    private var userName = ""
    private var relayURL: URL?
    private var retries = 0
    private var keepAlive: Timer?
    private var shouldReconnect = false

    private let maxRetries = 5

    // MARK: 入口

    func create(relay: URL, name: String) {
        pendingCreate = true
        pendingJoinCode = nil
        start(relay: relay, name: name)
    }

    func join(relay: URL, code: String, name: String) {
        pendingCreate = false
        pendingJoinCode = code.uppercased()
        start(relay: relay, name: name)
    }

    func close() {
        shouldReconnect = false
        retries = 0
        keepAlive?.invalidate()
        keepAlive = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .idle
        code = ""
        members = 0
        isHost = false
    }

    // MARK: 连接

    private func start(relay: URL, name: String) {
        close()
        shouldReconnect = true
        relayURL = relay
        userName = name
        state = .connecting
        connect()
    }

    private func connect() {
        guard let relayURL else { return }
        let task = session.webSocketTask(with: relayURL)
        self.task = task
        task.resume()
        receiveLoop(task)

        if pendingCreate {
            sendRaw(SyncPlayMessage(type: "create", name: userName))
        } else if let code = pendingJoinCode {
            sendRaw(SyncPlayMessage(type: "join", name: userName, code: code))
        }
        startKeepAlive()
        luLogInfo("SyncPlay", "中继连接 \(relayURL.absoluteString)")
    }

    private func startKeepAlive() {
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, let task = self.task else { return }
            task.sendPing { error in
                if let error {
                    luLogWarn("SyncPlay", "中继 ping 失败：\(error.localizedDescription)")
                    self.scheduleReconnect(reason: "连接已断开")
                }
            }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if self.shouldReconnect {
                    self.scheduleReconnect(reason: error.localizedDescription)
                } else {
                    self.state = .failed(error.localizedDescription)
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                @unknown default:
                    break
                }
                self.receiveLoop(task)
            }
        }
    }

    private func scheduleReconnect(reason: String) {
        guard shouldReconnect else {
            state = .failed(reason)
            return
        }
        keepAlive?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        guard retries < maxRetries else {
            state = .failed(reason)
            onClosed?("重连失败，请重新开房或加入")
            return
        }
        retries += 1
        state = .connecting
        let delay = min(Double(retries) * 1.6, 8)
        luLogWarn("SyncPlay", "中继断开，\(delay)s 后第 \(retries) 次重连")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.shouldReconnect else { return }
            // 重连时房间码还在：房主重新 create，观众重新 join
            if !self.pendingCreate, self.pendingJoinCode == nil, !self.code.isEmpty {
                self.pendingJoinCode = self.code
            }
            self.connect()
        }
    }

    // MARK: 收发

    func send(_ message: SyncPlayMessage) {
        sendRaw(message)
    }

    private func sendRaw(_ message: SyncPlayMessage) {
        guard let task, let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if let error {
                luLogWarn("SyncPlay", "中继发送失败：\(error.localizedDescription)")
                self?.scheduleReconnect(reason: error.localizedDescription)
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(SyncPlayMessage.self, from: data)
        else { return }

        switch message.type {
        case "created":
            code = message.code ?? ""
            members = 1
            isHost = true
            retries = 0
            state = .ready
            luLogInfo("SyncPlay", "中继房间已创建 \(code)")
        case "joined":
            code = message.code ?? ""
            members = message.members ?? 2
            isHost = false
            retries = 0
            state = .ready
            sendRaw(SyncPlayMessage(type: "hello", name: userName))
            luLogInfo("SyncPlay", "已加入中继房间 \(code)")
        case "peer":
            members = message.members ?? members
            onMessage?(message)
        case "pong":
            break
        case "error":
            state = .failed(message.text ?? "中继拒绝")
            shouldReconnect = false
            onClosed?(message.text ?? "房间不可用")
        default:
            onMessage?(message)
        }
    }
}

// MARK: - 局域网地址

/// 取本机 Wi-Fi 的 IPv4，方便同网段的人手输 `IP:端口` 加入（Bonjour 有时会被路由器拦）。
enum LuNetworkInfo {
    static func localIPv4() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return addresses }
        defer { freeifaddrs(pointer) }

        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = item.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let value = String(cString: host)
            if !value.isEmpty { addresses.append(value) }
        }
        return addresses
    }
}

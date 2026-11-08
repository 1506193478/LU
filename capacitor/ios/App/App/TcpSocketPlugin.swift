import Foundation
import Network
import Capacitor

/**
 * 原生 TCP 桥：为 Syncplay 协议（一起看）提供 socket 能力。
 * JS 端通过 Capacitor.Plugins.TcpSocket 调用，数据事件名 "luTcpData"。
 * 支持 STARTTLS 升级（Syncplay 协议 TLS 协商：新建同端点 TLS 连接替换）。
 */
@objc(TcpSocketPlugin)
public class TcpSocketPlugin: CAPPlugin {

    private var connection: NWConnection?
    private var pending = ""
    private let queue = DispatchQueue(label: "lu.tcp")

    @objc func connect(_ call: CAPPluginCall) {
        guard let host = call.getString("host"), !host.isEmpty else {
            call.reject("host required"); return
        }
        let port = call.getInt("port") ?? 8995
        let timeout = call.getInt("timeout") ?? 8000

        disconnectInternal()
        let params = NWParameters.tcp
        params.connectionTimeout = NWIntervalDuration(Double(timeout) / 1000.0)
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 8995,
                                using: params)
        connection = conn
        pending = ""

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.receiveLoop(conn)
                call.resolve(["ok": true])
            case .failed(let err):
                if !call.completed { call.reject("connect failed: \(err)") }
            case .cancelled:
                break
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// STARTTLS：向同一端点发起 TLS 连接并替换（Syncplay TLS 协商）
    @objc func startTls(_ call: CAPPluginCall) {
        guard let old = connection,
              case let ep = old.endpoint else {
            call.reject("not connected"); return
        }
        let tls = NWParameters(tls: nil)
        let conn = NWConnection(endpoint: ep, using: tls)
        connection = conn
        pending = ""
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.receiveLoop(conn)
                call.resolve()
            case .failed(let err):
                if !call.completed { call.reject("tls failed: \(err)") }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let data = call.getString("data")?.data(using: .utf8), let conn = connection else {
            call.reject("not connected"); return
        }
        conn.send(content: data, completion: .contentProcessed { err in
            if let err = err { call.reject("write failed: \(err)") } else { call.resolve() }
        })
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        disconnectInternal()
        call.resolve()
    }

    private func disconnectInternal() {
        connection?.cancel()
        connection = nil
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                if let text = String(data: data, encoding: .utf8) {
                    self.pending += text
                    while let idx = self.pending.firstIndex(of: "\n") {
                        let line = String(self.pending[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        self.pending.removeSubrange(...idx)
                        if !line.isEmpty { self.emit(line) }
                    }
                }
                self.receiveLoop(conn)
            } else if error == nil {
                self.bridge?.trigger("luTcpClose", data: nil)
            }
        }
    }

    private func emit(_ line: String) {
        var obj = JSObject()
        obj["data"] = line
        bridge?.trigger("luTcpData", data: obj)
    }
}

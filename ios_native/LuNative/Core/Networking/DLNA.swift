import Foundation
import Darwin

// MARK: - 设备模型

struct DLNADevice: Identifiable, Hashable {
    let id: String
    let name: String
    let location: URL
    let controlURL: URL?
    let modelName: String

    var isControllable: Bool { controlURL != nil }
}

// MARK: - SSDP 发现

/// 局域网 DLNA 投屏。
///
/// 发现用 SSDP（UDP 组播 M-SEARCH），控制用 UPnP AVTransport 的 SOAP 调用。
/// Network.framework 不暴露组播 socket 的 fd，所以这里直接用 BSD socket，
/// 放到后台队列跑，避免阻塞主线程。
final class DLNADiscovery {

    static let shared = DLNADiscovery()

    func discover(timeout: TimeInterval = 3.0) async -> [DLNADevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.performSearch(timeout: timeout))
            }
        }
    }

    private static func performSearch(timeout: TimeInterval) -> [DLNADevice] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            luLogError("DLNA", "socket 创建失败")
            return []
        }
        defer { close(fd) }

        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = 0
        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                bind(fd, address, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            luLogError("DLNA", "绑定本地端口失败")
            return []
        }

        let message = "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: 239.255.255.250:1900\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: 3\r\n"
            + "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"

        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        destination.sin_addr.s_addr = inet_addr("239.255.255.250")

        _ = message.withCString { pointer in
            withUnsafePointer(to: &destination) { address in
                address.withMemoryRebound(to: sockaddr.self, capacity: 1) { target in
                    sendto(fd, pointer, strlen(pointer), 0, target,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var locations: [String] = []
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(fd, &buffer, buffer.count, 0, address, &fromLength)
                }
            }
            guard received > 0 else { continue }
            guard let text = String(bytes: buffer[0..<received], encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("location:") else { continue }
                let value = trimmed.dropFirst("location:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !locations.contains(value) {
                    locations.append(value)
                }
            }
        }

        var devices: [DLNADevice] = []
        for location in locations {
            guard let url = URL(string: location), url.scheme?.hasPrefix("http") == true else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            if let device = parseDescription(data, location: url) {
                devices.append(device)
            }
        }
        luLogInfo("DLNA", "发现 \(devices.count) 台设备（\(locations.count) 个描述）")
        return devices
    }

    private static func parseDescription(_ data: Data, location: URL) -> DLNADevice? {
        // 设备描述是 XML，用 libxml2 封装（见 LuXML.swift）；XML 严格解析即可
        guard let document = LuXMLDocument(data: data, isHTML: false) else { return nil }

        func text(_ xpath: String) -> String? {
            document.nodes(xpath).first?.stringValue
        }

        let name = text("//*[local-name()='device']/*[local-name()='friendlyName']")
            ?? location.host ?? "DLNA 设备"
        let udn = text("//*[local-name()='device']/*[local-name()='UDN']") ?? location.absoluteString
        let model = text("//*[local-name()='device']/*[local-name()='modelName']") ?? ""

        var control: URL?
        let services = document.nodes("//*[local-name()='service']")
        for service in services {
            let type = service.nodes("./*[local-name()='serviceType']").first?.stringValue ?? ""
            guard type.contains("AVTransport") else { continue }
            let raw = service.nodes("./*[local-name()='controlURL']").first?.stringValue ?? ""
            guard !raw.isEmpty else { continue }
            control = URL(string: raw, relativeTo: location)?.absoluteURL
            break
        }

        guard control != nil else { return nil }   // 只保留可控制的 MediaRenderer
        return DLNADevice(id: udn, name: name, location: location,
                          controlURL: control, modelName: model)
    }
}

// MARK: - 控制

enum DLNAError: LocalizedError {
    case noControlURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noControlURL: return "该设备不支持 AVTransport 控制"
        case .badResponse: return "设备没有正确响应"
        }
    }
}

final class DLNAController {
    static let shared = DLNAController()

    private let serviceURN = "urn:schemas-upnp-org:service:AVTransport:1"

    func cast(device: DLNADevice, stream: PlayStream, title: String) async throws {
        guard let control = device.controlURL else { throw DLNAError.noControlURL }
        let metadata = didl(title: title, url: stream.url.absoluteString)
        try await soap(control: control, action: "SetAVTransportURI", body: """
        <InstanceID>0</InstanceID>
        <CurrentURI>\(escape(stream.url.absoluteString))</CurrentURI>
        <CurrentURIMetaData>\(escape(metadata))</CurrentURIMetaData>
        """)
        try await play(device: device)
    }

    func play(device: DLNADevice) async throws {
        guard let control = device.controlURL else { throw DLNAError.noControlURL }
        try await soap(control: control, action: "Play", body: """
        <InstanceID>0</InstanceID>
        <Speed>1</Speed>
        """)
    }

    func pause(device: DLNADevice) async throws {
        guard let control = device.controlURL else { throw DLNAError.noControlURL }
        try await soap(control: control, action: "Pause", body: "<InstanceID>0</InstanceID>")
    }

    func stop(device: DLNADevice) async throws {
        guard let control = device.controlURL else { throw DLNAError.noControlURL }
        try await soap(control: control, action: "Stop", body: "<InstanceID>0</InstanceID>")
    }

    func seek(device: DLNADevice, seconds: Double) async throws {
        guard let control = device.controlURL else { throw DLNAError.noControlURL }
        let total = Int(max(seconds, 0))
        let stamp = String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        try await soap(control: control, action: "Seek", body: """
        <InstanceID>0</InstanceID>
        <Unit>REL_TIME</Unit>
        <Target>\(stamp)</Target>
        """)
    }

    // MARK: SOAP

    private func soap(control: URL, action: String, body: String) async throws {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="\(serviceURN)">\(body)</u:\(action)></s:Body>
        </s:Envelope>
        """
        var request = HttpRequest(method: "POST", url: control)
        request.body = envelope.data(using: .utf8)
        request.timeout = 8
        request.headers["Content-Type"] = "text/xml; charset=\"utf-8\""
        request.headers["SOAPACTION"] = "\"\(serviceURN)#\(action)\""
        do {
            _ = try await HttpClient.shared.send(request)
            luLogInfo("DLNA", "\(action) 成功 \(control.host ?? "")")
        } catch {
            luLogError("DLNA", "\(action) 失败：\(error.localizedDescription)")
            throw error
        }
    }

    private func didl(title: String, url: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
        <item id="0" parentID="-1" restricted="1">
        <dc:title>\(escape(title))</dc:title>
        <upnp:class>object.item.videoItem</upnp:class>
        <res protocolInfo="http-get:*:video/mp4:*">\(escape(url))</res>
        </item></DIDL-Lite>
        """
    }

    private func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

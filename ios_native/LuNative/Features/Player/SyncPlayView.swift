import SwiftUI
import UIKit

/// 一起看。
///
/// 两条通道：
/// - **局域网**：本机起 WebSocket 服务（9301），Bonjour 广播 `_lu-sync._tcp`，
///   同 Wi-Fi 的设备自动发现或手输 `IP:端口`；
/// - **跨网中继**：双方连一台公网 WebSocket 中继（`server/lu-sync-relay.ts`），
///   房主拿 5 位房间码，朋友在任何网络下输入房间码即可加入。
///
/// 房间状态以房主为准：房主切集/暂停/拖动会广播；观众的操作先到房主，
/// 房主应用到本地播放器后再广播给所有人。
struct SyncPlayView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var session = SyncPlaySession.shared
    @ObservedObject private var server = SyncPlayServer.shared
    @StateObject private var browser = SyncPlayBrowser()

    private enum JoinMode: String, CaseIterable {
        case lan = "局域网"
        case relay = "跨网络"
    }

    @State private var joinMode: JoinMode = .lan
    @State private var hostMode: JoinMode = .lan
    @State private var address = ""
    @State private var joinCode = ""
    @State private var chatText = ""

    private let emojis = ["👍", "😂", "😭", "😱", "🔥", "❤️", "🎉", "🤔", "😴", "🍿", "👀", "💯"]
    private let stickers = ["前排", "泪目", "神作", "这集封神", "别剧透", "再来一集"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LuPageHeader(title: "一起看", subtitle: "局域网直连，或用房间码跨网络")

                statusCard

                if session.role == .none {
                    hostCard
                    joinCard
                    if !browser.hosts.isEmpty && joinMode == .lan {
                        nearbyCard
                    }
                } else {
                    chatCard
                }

                LuGroup(title: "怎么用") {
                    VStack(alignment: .leading, spacing: 8) {
                        step("1", "房主选「局域网」或「跨网络」开房，拿到房间号 / IP 地址")
                        step("2", "同一个 Wi-Fi 选局域网；不在一个网就选跨网络，填中继地址 + 房间号")
                        step("3", "双方各自打开同一集，播放器的暂停、切集、拖动进度会同步")
                        Text("跨网络依赖中继：仓库里的 `server/lu-sync-relay.ts` 用 Deno 一行命令就能跑起来（或部署到 Deno Deploy），中继只转发不存储。")
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.tertiary)
                            .padding(.top, 2)
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, LuTheme.pagePadding)
            .padding(.bottom, 28)
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    // MARK: 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(session.role.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.role == .none ? LuTheme.secondary : LuTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(LuTheme.accent.opacity(session.role == .none ? 0 : 0.14)))

                if session.role != .none {
                    Text(session.mode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LuTheme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }

                Spacer()

                Text(session.statusText)
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)
            }

            if session.role != .none {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(session.roomCode.isEmpty ? "—" : session.roomCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(LuTheme.label)
                        .textSelection(.enabled)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("房间号")
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.tertiary)
                        Text("\(session.members) 人在线")
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.secondary)
                    }
                    Spacer()
                    Button {
                        session.leave()
                        LuHUD.shared.show("已离开房间")
                    } label: {
                        Text("离开")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                if session.role == .host {
                    if session.mode == .lan {
                        if !session.lanAddresses.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 11))
                                    .foregroundStyle(LuTheme.accent)
                                Text(session.lanAddresses.joined(separator: "  ·  "))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(LuTheme.secondary)
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = session.lanAddresses.first
                                    LuHUD.shared.show("地址已复制")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(LuTheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if !settings.syncRelayURL.isEmpty {
                        Button {
                            UIPasteboard.general.string =
                                "LU 一起看 · 房间 \(session.roomCode) · 中继 \(settings.syncRelayURL)"
                            LuHUD.shared.show("邀请信息已复制")
                        } label: {
                            Label("复制邀请信息", systemImage: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LuTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("开房或加入后，播放器顶部会出现同步状态。")
                    .font(.system(size: 12))
                    .foregroundStyle(LuTheme.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luLiquidGlass(cornerRadius: 18, frost: 0.5, saturation: 1.4, aberration: 0.4,
                       refraction: 0)
        .animation(LuMotion.quick, value: session.roomCode)
        .animation(LuMotion.quick, value: session.members)
    }

    // MARK: 开房

    private var hostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开一个房间")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)

            Picker("通道", selection: $hostMode) {
                ForEach(JoinMode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(hostMode == .lan
                 ? "在本机 9301 端口起服务并广播 Bonjour，同一 Wi-Fi 才能加入。"
                 : "通过公网中继配对，任何网络都能加入。需要先有一台中继服务器。")
                .font(LuTheme.caption())
                .foregroundStyle(LuTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hostMode == .relay {
                relayField
            }

            LuLiquidButton(tint: LuTheme.accent.opacity(0.9)) {
                session.startHosting(relayURL: hostMode == .relay ? settings.syncRelayURL : "")
                LuHUD.shared.show(hostMode == .relay ? "正在连中继…" : "房间已开启")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: hostMode == .relay ? "globe" : "wifi")
                    Text("开房")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
            }
            .disabled(hostMode == .relay && settings.syncRelayURL.isEmpty)

            if let error = server.lastError, hostMode == .lan {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
            if hostMode == .relay && settings.syncRelayURL.isEmpty {
                Text("先填中继地址，例如 wss://lu-sync.deno.dev")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .luGlass(.thin, cornerRadius: 14)
    }

    private var relayField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("中继地址")
                .font(.system(size: 11))
                .foregroundStyle(LuTheme.tertiary)
            TextField("wss://lu-sync.deno.dev", text: $settings.syncRelayURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill)))
        }
    }

    // MARK: 加入

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("加入房间")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)

            Picker("通道", selection: $joinMode) {
                ForEach(JoinMode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if joinMode == .lan {
                HStack(spacing: 8) {
                    TextField("192.168.1.8:9301", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .tertiarySystemFill)))
                    Button {
                        session.join(address: address, name: settings.syncPlayName)
                    } label: {
                        Text("加入")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 42)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(address.isEmpty ? Color.gray : LuTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(address.isEmpty)
                }
                Text("也可以只填 IP，默认端口 9301。")
                    .font(.system(size: 11))
                    .foregroundStyle(LuTheme.tertiary)
            } else {
                relayField
                HStack(spacing: 8) {
                    TextField("房间号", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .tertiarySystemFill)))
                    Button {
                        session.join(relayURL: settings.syncRelayURL,
                                     code: joinCode,
                                     name: settings.syncPlayName)
                    } label: {
                        Text("加入")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 42)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(joinCode.isEmpty ? Color.gray : LuTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(joinCode.isEmpty || settings.syncRelayURL.isEmpty)
                }
            }
        }
        .padding(14)
        .luGlass(.thin, cornerRadius: 14)
    }

    private var nearbyCard: some View {
        LuGroup(title: "附近的房间") {
            ForEach(browser.hosts.indices, id: \.self) { index in
                let host = browser.hosts[index]
                Button {
                    session.join(endpoint: host.endpoint, name: settings.syncPlayName)
                    LuHUD.shared.show("正在连接 \(host.name)")
                } label: {
                    LuListRow(title: host.name, symbol: "dot.radiowaves.left.and.right",
                              chevron: true)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                if index < browser.hosts.count - 1 {
                    Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 52)
                }
            }
        }
    }

    // MARK: 聊天

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("房间聊天")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
                Spacer()
                Text("\(session.messages.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(LuTheme.tertiary)
            }

            if session.messages.isEmpty {
                Text("还没人说话。聊聊这集剧情，或者提醒对方「我要暂停一下」。")
                    .font(.system(size: 12))
                    .foregroundStyle(LuTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(session.messages) { line in
                                chatRow(line).id(line.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: session.messages.count) { _ in
                        if let last = session.messages.last {
                            withAnimation(LuMotion.quick) { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            session.sendChat(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 17))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                    Rectangle()
                        .fill(LuTheme.hairline)
                        .frame(width: 0.5, height: 20)
                        .padding(.horizontal, 2)
                    ForEach(stickers, id: \.self) { sticker in
                        Button {
                            session.sendChat(sticker)
                        } label: {
                            Text(sticker)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LuTheme.accent)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Capsule().fill(LuTheme.accent.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("说点什么…", text: $chatText)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .tertiarySystemFill)))
                    .onSubmit(sendChat)
                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(chatText.isEmpty ? LuTheme.tertiary : LuTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(chatText.isEmpty)
            }
        }
        .padding(14)
        .luGlass(.thin, cornerRadius: 14)
    }

    private func chatRow(_ line: SyncPlayChat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(line.isMine ? LuTheme.accent : LuTheme.secondary)
            Text(line.text)
                .font(.system(size: 13))
                .foregroundStyle(LuTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func sendChat() {
        let text = chatText
        chatText = ""
        session.sendChat(text)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(LuTheme.accent))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(LuTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

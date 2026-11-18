import SwiftUI
import UIKit

struct EmbySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LuPageHeader(title: "Emby 服务器")

                    if let session = settings.embySession {
                        LuGroup(title: "已连接") {
                            LuListRow(title: session.userName, subtitle: session.serverURL.absoluteString,
                                      symbol: "person.crop.circle.badge.checkmark", tint: .green)
                                .padding(.horizontal, 12)
                            line
                            Button {
                                settings.embySession = nil
                                LuHUD.shared.show("已断开连接")
                            } label: {
                                HStack {
                                    Text("断开连接").font(.system(size: 15)).foregroundStyle(.red)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .frame(height: LuTheme.rowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        LuGroup(title: "登录") {
                            field("服务器地址", text: $server, keyboard: .URL,
                                  placeholder: "http://192.168.1.10:8096")
                            line
                            field("用户名", text: $username)
                            line
                            secureField("密码", text: $password)
                        }

                        if let error {
                            Text(error)
                                .font(LuTheme.caption())
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await login() }
                        } label: {
                            HStack(spacing: 8) {
                                if isWorking { ProgressView().tint(.white) }
                                Text(isWorking ? "连接中…" : "连接")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(canSubmit ? LuTheme.accent : Color.gray))
                        }
                        .buttonStyle(LuCardButtonStyle())
                        .disabled(!canSubmit || isWorking)

                        Text("地址需带 http:// 或 https:// 前缀。局域网内可直接填内网 IP，外网访问请配置端口映射或反向代理。")
                            .font(.system(size: 12))
                            .foregroundStyle(LuTheme.tertiary)
                            .lineSpacing(2)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)

            VStack {
                HStack {
                    LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var line: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 12)
    }

    private func field(_ title: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default,
                       placeholder: String = "") -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LuTheme.label)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .frame(height: LuTheme.rowHeight)
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LuTheme.label)
            Spacer()
            SecureField("", text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .frame(height: LuTheme.rowHeight)
    }

    private func login() async {
        guard let url = normalizedURL(server) else {
            error = "服务器地址无效"
            return
        }
        isWorking = true
        error = nil
        do {
            let session = try await EmbyAPI.shared.authenticate(server: url,
                                                                username: username.trimmingCharacters(in: .whitespaces),
                                                                password: password)
            settings.embySession = session
            LuHUD.shared.show("已连接 \(session.userName)")
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }

    private func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.hasPrefix("http") { text = "http://" + text }
        if text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

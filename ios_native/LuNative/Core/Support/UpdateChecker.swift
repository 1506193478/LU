import SwiftUI

// MARK: - 版本

struct LuRelease: Identifiable {
    var id: String { tag }
    let tag: String
    let version: String
    let name: String
    let notes: String
    let pageURL: URL
    let ipaURL: URL?
    let publishedAt: String
    let isNative: Bool
}

/// 应用内更新检查。
///
/// 走 GitHub Releases（仓库 `1506193478/LU`）。原生线用 `ios-v*` 前缀打 tag，
/// 老 Flutter 线的 `4.x` tag 只作为参考信息展示，不参与升级判断。
final class UpdateChecker {
    static let shared = UpdateChecker()

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private let endpoint = "https://api.github.com/repos/1506193478/LU/releases?per_page=30"

    func fetchReleases() async throws -> [LuRelease] {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.transport("非 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 403 { throw NetworkError.badStatus(403, "GitHub API 限流，稍后再试") }
            throw NetworkError.badStatus(http.statusCode, nil)
        }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.decoding("releases 不是数组")
        }

        return array.compactMap { item -> LuRelease? in
            guard let tag = item["tag_name"] as? String,
                  let page = item["html_url"] as? String,
                  let pageURL = URL(string: page) else { return nil }
            let name = item["name"] as? String ?? tag
            let notes = item["body"] as? String ?? ""
            let published = item["published_at"] as? String ?? ""

            var ipa: URL?
            if let assets = item["assets"] as? [[String: Any]] {
                for asset in assets {
                    guard let assetName = asset["name"] as? String,
                          assetName.lowercased().hasSuffix(".ipa"),
                          let raw = asset["browser_download_url"] as? String,
                          let url = URL(string: raw) else { continue }
                    ipa = url
                    break
                }
            }
            let lower = tag.lowercased()
            let isNative = lower.hasPrefix("ios-") || lower.contains("ios") || ipa != nil
            let version = tag.replacingOccurrences(of: "ios-v", with: "")
                .replacingOccurrences(of: "ios-", with: "")
                .replacingOccurrences(of: "v", with: "", options: .anchored)
            return LuRelease(tag: tag, version: version, name: name, notes: notes,
                             pageURL: pageURL, ipaURL: ipa, publishedAt: published,
                             isNative: isNative)
        }
    }

    func latestNative() async throws -> LuRelease? {
        let releases = try await fetchReleases()
        return releases.first { $0.isNative }
    }

    /// 语义化版本比较，返回 a 是否比 b 新。
    static func isNewer(_ a: String, than b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        let right = b.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - 更新界面

struct UpdateSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var error: String?
    @State private var native: LuRelease?
    @State private var flutter: LuRelease?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(LuTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LU 原生版")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LuTheme.label)
                            Text("当前 \(UpdateChecker.currentVersion) (\(UpdateChecker.currentBuild))")
                                .font(LuTheme.caption())
                                .foregroundStyle(LuTheme.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .luGlass(.thin, cornerRadius: 12)

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在检查 GitHub Releases…")
                                .font(LuTheme.caption())
                                .foregroundStyle(LuTheme.secondary)
                        }
                        .padding(.vertical, 20)
                    } else if let error {
                        Text(error)
                            .font(LuTheme.caption())
                            .foregroundStyle(.red)
                        Button("重新检查") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LuTheme.accent)
                    } else {
                        if let native {
                            releaseCard(native, badge: "原生 iOS")
                        } else {
                            Text("仓库里还没有 `ios-v*` 的原生版本发布。当前是开发构建，更新检查会在第一次 iOS 发版后生效。")
                                .font(LuTheme.caption())
                                .foregroundStyle(LuTheme.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .luGlass(.thin, cornerRadius: 12)
                        }

                        if let flutter {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("参考：Flutter 主线最新 \(flutter.version)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(LuTheme.label)
                                Text("两条线版本号体系不同，Flutter 版本不适用于原生 App。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(LuTheme.tertiary)
                                Link("打开 Release 页面", destination: flutter.pageURL)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LuTheme.accent)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .luGlass(.thin, cornerRadius: 12)
                        }
                    }

                    Text("iOS 侧正式分发需要 Apple Developer 账号与 TestFlight / App Store，App 内不会静默安装 ipa。")
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .navigationTitle("检查更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func releaseCard(_ release: LuRelease, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(release.version)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LuTheme.label)
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LuTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(LuTheme.accent.opacity(0.14)))
                Spacer()
                if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion) {
                    Text("有新版本")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green))
                }
            }
            if !release.publishedAt.isEmpty {
                Text(String(release.publishedAt.prefix(10)))
                    .font(.system(size: 11))
                    .foregroundStyle(LuTheme.tertiary)
            }
            if !release.notes.isEmpty {
                Text(release.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(LuTheme.secondary)
                    .lineSpacing(3)
                    .lineLimit(12)
            }
            HStack(spacing: 12) {
                Link(destination: release.pageURL) {
                    Text("查看发布页")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(LuTheme.accent))
                }
                if let ipa = release.ipaURL {
                    ShareLink(item: ipa) {
                        Text("导出 ipa 链接")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LuTheme.accent)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luGlass(.thin, cornerRadius: 12)
    }

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
        do {
            let releases = try await UpdateChecker.shared.fetchReleases()
            native = releases.first { $0.isNative }
            flutter = releases.first { !$0.isNative }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

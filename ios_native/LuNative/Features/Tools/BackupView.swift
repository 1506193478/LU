import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：收藏、历史、插件、常用设置打成一个 JSON。
/// 导出走系统分享（可存「文件」/ 发给自己），导入走文件选择器。
struct BackupView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var plugins: PluginStore

    @State private var exported: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LuPageHeader(title: "备份与恢复", subtitle: "收藏 · 历史 · 插件 · 设置")

                LuGroup(title: "当前数据") {
                    LuListRow(title: "追番", value: "\(app.collects.count) 部")
                        .padding(.horizontal, 12)
                    divider
                    LuListRow(title: "观看历史", value: "\(app.history.count) 条")
                        .padding(.horizontal, 12)
                    divider
                    LuListRow(title: "播放源插件", value: "\(plugins.plugins.count) 个")
                        .padding(.horizontal, 12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button(action: doExport) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("生成备份文件")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(LuTheme.accent))
                    }
                    .buttonStyle(LuCardButtonStyle())

                    if let exported {
                        ShareLink(item: exported) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                Text("分享 \(exported.lastPathComponent)")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LuTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .luGlass(.thin, cornerRadius: 12)
                        }
                    }

                    Button {
                        importing = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc")
                            Text("从文件恢复")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LuTheme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .luGlass(.thin, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }

                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(failed ? .red : LuTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("恢复是合并式的：同 id 以备份为准，不会删掉本地多出来的条目。\n敏感信息（Bangumi Token、弹弹play Secret、Emby / WebDAV 密码）不会写进备份。")
                    .font(.system(size: 11))
                    .foregroundStyle(LuTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, LuTheme.pagePadding)
            .padding(.bottom, 28)
        }
        .background(LuTheme.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private var divider: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 12)
    }

    private func doExport() {
        do {
            let url = try LuBackupService.export()
            exported = url
            failed = false
            message = "已生成 \(url.lastPathComponent)，可以存到「文件」或发给自己。"
            LuHUD.shared.show("备份已生成")
        } catch {
            failed = true
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            failed = true
            message = "选择文件失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let summary = try LuBackupService.restore(from: url)
                failed = false
                message = "已恢复：\(summary.collects) 部追番、\(summary.history) 条历史、\(summary.plugins) 个插件。"
                LuHUD.shared.show("恢复完成")
            } catch {
                failed = true
                message = "恢复失败：\(error.localizedDescription)"
            }
        }
    }
}

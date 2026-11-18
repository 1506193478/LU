import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    LuPageHeader(title: "观看历史", subtitle: "\(app.history.count) 条") {
                        if !app.history.isEmpty {
                            Button("清空") {
                                withAnimation(LuTheme.spring) { app.clearHistory() }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                        }
                    }

                    if app.history.isEmpty {
                        LuEmptyState(symbol: "clock", title: "还没有观看记录")
                    } else {
                        ForEach(app.history) { record in
                            NavigationLink(value: Route.detail(subjectID: record.subjectID)) {
                                row(record)
                            }
                            .buttonStyle(.plain)
                        }
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

    private func row(_ record: HistoryRecord) -> some View {
        HStack(spacing: 12) {
            LuRemoteImage(url: URL(string: record.cover.hasPrefix("//") ? "https:" + record.cover : record.cover))
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(record.subjectName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
                    .lineLimit(1)
                Text(record.episodeName)
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(uiColor: .tertiarySystemFill))
                        Capsule().fill(LuTheme.accent)
                            .frame(width: geo.size.width * record.progress)
                    }
                }
                .frame(height: 3)
                Text("\(Int(record.progress * 100))% · \(relativeTime(record.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(LuTheme.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .luGlass(.thin, cornerRadius: 12)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

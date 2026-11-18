import Foundation
import UserNotifications

/// 追番更新提醒。
///
/// 用本地通知：按收藏里每部番的 `airWeekday`（1 = 周一）建 7 条每周重复的提醒，
/// 当天 20:00 弹出「今天更新的番」。不依赖服务端推送，也不需要联网。
final class LuUpdateReminder {
    static let shared = LuUpdateReminder()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "lu.update."
    private var asking = false

    private init() {}

    /// 启动时调用：开关开着就确保通知已排好（收藏变了也会重排）
    func refreshIfNeeded() {
        guard AppSettings.shared.updateReminder else { return }
        ensurePermission { [weak self] granted in
            guard granted else { return }
            self?.schedule()
        }
    }

    /// 设置页开关
    func setEnabled(_ enabled: Bool) {
        AppSettings.shared.updateReminder = enabled
        guard enabled else {
            clear()
            LuHUD.shared.show("已关闭更新提醒")
            return
        }
        ensurePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.schedule()
                LuHUD.shared.show("每天 20:00 提醒今天更新的番")
            } else {
                AppSettings.shared.updateReminder = false
                LuHUD.shared.show("通知权限被拒绝，请到系统设置里开启")
            }
        }
    }

    /// 收藏变化后主动重排
    func refresh() {
        guard AppSettings.shared.updateReminder else { return }
        schedule()
    }

    private func clear() {
        center.removePendingNotificationRequests(withIdentifiers: ids())
    }

    private func ids() -> [String] {
        (1...7).map { "\(identifierPrefix)\($0)" }
    }

    private func ensurePermission(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            default:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            }
        }
    }

    private func schedule() {
        let subjects = AppState.shared.collects.map(\.subject)
        center.removePendingNotificationRequests(withIdentifiers: ids())
        guard !subjects.isEmpty else { return }

        for day in 1...7 {
            let titles = subjects.filter { $0.airWeekday == day }.map(\.displayName)
            guard !titles.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "今天更新的番"
            let head = titles.prefix(4).joined(separator: "、")
            content.body = titles.count > 4 ? "\(head) 等 \(titles.count) 部" : head
            content.sound = .default

            var components = DateComponents()
            // Calendar 的 weekday 1 = 周日，Bangumi 的 1 = 周一
            components.weekday = day % 7 + 1
            components.hour = 20
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(day)",
                                                content: content, trigger: trigger)
            center.add(request)
        }
        luLogInfo("Reminder", "已排 \(subjects.count) 部追番的周更提醒")
    }
}

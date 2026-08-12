import Combine
import Foundation
import UserNotifications

@MainActor
final class CoachNotificationManager: ObservableObject {
    enum State: Equatable {
        case unknown
        case requesting
        case authorized
        case denied
        case failed

        var title: String {
            switch self {
            case .unknown: "尚未设置提醒"
            case .requesting: "正在请求通知权限"
            case .authorized: "教练提醒已就绪"
            case .denied: "系统通知权限已关闭"
            case .failed: "暂时无法设置提醒"
            }
        }

        var detail: String {
            switch self {
            case .unknown: "开启后每天最多收到一条与当前记录有关的提醒。"
            case .requesting: "请在系统弹窗中选择是否允许轻衡发送通知。"
            case .authorized: "每天早上结合昨日饮食、运动、睡眠和体重趋势生成一条晨报。"
            case .denied: "请在系统设置中允许轻衡通知后再开启。"
            case .failed: "系统没有完成提醒设置，可以稍后再试。"
            }
        }

        var symbol: String {
            switch self {
            case .authorized: "bell.badge.fill"
            case .denied, .failed: "bell.slash.fill"
            case .requesting: "hourglass"
            case .unknown: "bell.fill"
            }
        }

        var isAuthorized: Bool { self == .authorized }
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var scheduledSummary: String?

    private let center = UNUserNotificationCenter.current()
    private static let requestPrefix = "qingheng.coach."
    private static let morningIdentifiers = (0..<7).map { "\(requestPrefix)morning.\($0)" }
    private static let legacyIdentifiers = (1...7).map { "\(requestPrefix)weekday.\($0)" }
    private static let requestIdentifiers = morningIdentifiers + legacyIdentifiers

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            state = .authorized
        case .denied:
            state = .denied
        case .notDetermined:
            state = .unknown
        @unknown default:
            state = .failed
        }
    }

    func requestAuthorization() async -> Bool {
        state = .requesting
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()
            return granted && state.isAuthorized
        } catch {
            state = .failed
            return false
        }
    }

    func updateSchedule(
        morningBrief: CoachBrief,
        enabled: Bool,
        hour: Int,
        minute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        guard enabled else {
            removeScheduledReminders()
            return
        }

        await refreshAuthorizationStatus()
        guard state.isAuthorized else {
            scheduledSummary = nil
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: Self.requestIdentifiers)

        let safeHour = min(max(hour, 0), 23)
        let safeMinute = min(max(minute, 0), 59)
        let firstDate = Self.nextReminderDate(
            hour: safeHour,
            minute: safeMinute,
            now: now,
            calendar: calendar
        )

        do {
            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: firstDate) else {
                    continue
                }
                let content = UNMutableNotificationContent()
                if offset == 0 {
                    content.title = "轻衡晨报 · \(morningBrief.headline)"
                    content.body = String(morningBrief.message.prefix(150))
                    content.userInfo = [
                        "destination": "today",
                        "coachSource": morningBrief.source.title
                    ]
                } else {
                    content.title = "轻衡晨报"
                    content.body = "打开轻衡后，我会用最新的昨日饮食、运动、睡眠和体重趋势更新今天的一步建议。"
                    content.userInfo = ["destination": "today"]
                }
                content.sound = .default
                content.threadIdentifier = "qingheng.coach"

                try await center.add(
                    request(
                        identifier: Self.morningIdentifiers[offset],
                        date: date,
                        calendar: calendar,
                        content: content
                    )
                )
            }

            scheduledSummary = String(
                format: "每天 %02d:%02d · 优先发送昨日复盘晨报",
                safeHour,
                safeMinute
            )
        } catch {
            state = .failed
            scheduledSummary = nil
        }
    }

    func removeScheduledReminders() {
        center.removePendingNotificationRequests(withIdentifiers: Self.requestIdentifiers)
        scheduledSummary = nil
    }

    private func request(
        identifier: String,
        date: Date,
        calendar: Calendar,
        content: UNNotificationContent
    ) -> UNNotificationRequest {
        var components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )
        components.second = 0

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    nonisolated static func nextReminderDate(
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let safeHour = min(max(hour, 0), 23)
        let safeMinute = min(max(minute, 0), 59)
        let today = calendar.date(
            bySettingHour: safeHour,
            minute: safeMinute,
            second: 0,
            of: now
        ) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
            ?? now.addingTimeInterval(86_400)
    }
}

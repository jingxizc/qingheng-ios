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
            case .authorized: "周一至周六发送今日一步，周日改为本周复盘。"
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
    private static let requestIdentifiers = (1...7).map { "\(requestPrefix)weekday.\($0)" }

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
        context: CoachContext,
        weeklyReport: WeeklyCoachReport,
        enabled: Bool,
        hour: Int,
        minute: Int
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
        let dailyBrief = LocalCoachEngine.brief(for: context)

        do {
            for weekday in 2...7 {
                let content = UNMutableNotificationContent()
                content.title = dailyBrief.headline
                content.body = String(dailyBrief.message.prefix(110))
                content.sound = .default
                content.threadIdentifier = "qingheng.coach"
                content.userInfo = ["destination": "today"]

                try await center.add(
                    request(
                        identifier: "\(Self.requestPrefix)weekday.\(weekday)",
                        weekday: weekday,
                        hour: safeHour,
                        minute: safeMinute,
                        content: content
                    )
                )
            }

            let weeklyContent = UNMutableNotificationContent()
            weeklyContent.title = "轻衡 · 本周复盘"
            weeklyContent.body = String(
                "\(weeklyReport.headline)：\(weeklyReport.nextGoal)".prefix(110)
            )
            weeklyContent.sound = .default
            weeklyContent.threadIdentifier = "qingheng.coach"
            weeklyContent.userInfo = ["destination": "weeklyReport"]

            try await center.add(
                request(
                    identifier: "\(Self.requestPrefix)weekday.1",
                    weekday: 1,
                    hour: safeHour,
                    minute: safeMinute,
                    content: weeklyContent
                )
            )

            scheduledSummary = String(
                format: "每天 %02d:%02d · 周日发送周报",
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
        weekday: Int,
        hour: Int,
        minute: Int,
        content: UNNotificationContent
    ) -> UNNotificationRequest {
        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
    }
}

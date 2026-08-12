import Combine
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum CoachAction: String, Equatable, Sendable {
    case weigh
    case logMeal
    case reviewMeals
    case viewProgress
    case none
}

enum CoachSource: Equatable, Sendable {
    case localEngine
    case appleFoundationModel
    case qwenCloud

    var title: String {
        switch self {
        case .localEngine: "本机教练"
        case .appleFoundationModel: "Apple 端侧模型"
        case .qwenCloud: "Qwen3.7 Flash"
        }
    }
}

struct CoachBrief: Equatable, Sendable {
    let headline: String
    let message: String
    let actionTitle: String
    let action: CoachAction
    let symbol: String
    let source: CoachSource

    func replacingMessage(_ message: String, source: CoachSource) -> CoachBrief {
        CoachBrief(
            headline: headline,
            message: message,
            actionTitle: actionTitle,
            action: action,
            symbol: symbol,
            source: source
        )
    }
}

struct CoachContext: Equatable {
    let currentWeight: Double?
    let targetWeight: Double
    let sevenDayChange: Double?
    let weighedToday: Bool
    let todayMealCount: Int
    let todayAnalyzedMealCount: Int
    let todayCaloriesLow: Int?
    let todayCaloriesHigh: Int?
    let todayGroups: [FoodGroup]
    let mealRecordingStreak: Int
    let weightDaysInLastSevenDays: Int
    let hour: Int
    let previousDay: Date?
    let previousDayMealCount: Int
    let previousDayAnalyzedMealCount: Int
    let previousDayCaloriesLow: Int?
    let previousDayCaloriesHigh: Int?
    let previousDayGroups: [FoodGroup]
    let previousDayHealth: DailyHealthSummary?

    static func make(
        weights: [WeightRecord],
        meals: [MealRecord],
        targetWeight: Double,
        previousDayHealth: DailyHealthSummary? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CoachContext {
        let sortedWeights = weights.sorted { $0.measuredAt > $1.measuredAt }
        let currentWeight = sortedWeights.first?.weightKg
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let weeklyWeights = sortedWeights.filter { $0.measuredAt >= weekStart }
        let sevenDayChange: Double?
        if let newest = weeklyWeights.first, let oldest = weeklyWeights.last, weeklyWeights.count > 1 {
            sevenDayChange = newest.weightKg - oldest.weightKg
        } else {
            sevenDayChange = nil
        }

        let todayMeals = meals.filter { calendar.isDate($0.eatenAt, inSameDayAs: now) }
        let lows = todayMeals.compactMap(\.estimatedCaloriesLow)
        let highs = todayMeals.compactMap(\.estimatedCaloriesHigh)
        var seenGroups = Set<FoodGroup>()
        let groups = todayMeals
            .flatMap(\.analysisGroups)
            .filter { seenGroups.insert($0).inserted }

        let mealDays = Set(meals.map { calendar.startOfDay(for: $0.eatenAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        while mealDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let weightDays = Set(weeklyWeights.map { calendar.startOfDay(for: $0.measuredAt) })
        let today = calendar.startOfDay(for: now)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: today)
        let previousMeals = previousDay.map { day in
            meals.filter { calendar.isDate($0.eatenAt, inSameDayAs: day) }
        } ?? []
        let previousLows = previousMeals.compactMap(\.estimatedCaloriesLow)
        let previousHighs = previousMeals.compactMap(\.estimatedCaloriesHigh)
        var seenPreviousGroups = Set<FoodGroup>()
        let previousGroups = previousMeals
            .flatMap(\.analysisGroups)
            .filter { seenPreviousGroups.insert($0).inserted }

        return CoachContext(
            currentWeight: currentWeight,
            targetWeight: targetWeight,
            sevenDayChange: sevenDayChange,
            weighedToday: sortedWeights.first.map { calendar.isDate($0.measuredAt, inSameDayAs: now) } ?? false,
            todayMealCount: todayMeals.count,
            todayAnalyzedMealCount: todayMeals.filter(\.hasAnalysis).count,
            todayCaloriesLow: lows.isEmpty ? nil : lows.reduce(0, +),
            todayCaloriesHigh: highs.isEmpty ? nil : highs.reduce(0, +),
            todayGroups: groups,
            mealRecordingStreak: streak,
            weightDaysInLastSevenDays: weightDays.count,
            hour: calendar.component(.hour, from: now),
            previousDay: previousDay,
            previousDayMealCount: previousMeals.count,
            previousDayAnalyzedMealCount: previousMeals.filter(\.hasAnalysis).count,
            previousDayCaloriesLow: previousLows.isEmpty ? nil : previousLows.reduce(0, +),
            previousDayCaloriesHigh: previousHighs.isEmpty ? nil : previousHighs.reduce(0, +),
            previousDayGroups: previousGroups,
            previousDayHealth: previousDayHealth
        )
    }

    var promptDescription: String {
        let weightText = currentWeight.map { String(format: "%.1f kg", $0) } ?? "无"
        let changeText = sevenDayChange.map { String(format: "%+.1f kg", $0) } ?? "数据不足"
        let caloriesText: String
        if let todayCaloriesLow, let todayCaloriesHigh {
            caloriesText = "照片估算 \(todayCaloriesLow)-\(todayCaloriesHigh) 千卡"
        } else {
            caloriesText = "无估算"
        }
        let groupText = todayGroups.map(\.title).joined(separator: "、")
        let previousCaloriesText: String
        if let previousDayCaloriesLow, let previousDayCaloriesHigh {
            previousCaloriesText = "照片估算 \(previousDayCaloriesLow)-\(previousDayCaloriesHigh) 千卡"
        } else {
            previousCaloriesText = "无完整热量估算"
        }
        let previousGroupText = previousDayGroups.map(\.title).joined(separator: "、")
        let healthText = previousDayHealth?.compactText ?? "未授权或暂无数据"

        return """
        当前体重：\(weightText)；目标：\(String(format: "%.1f kg", targetWeight))
        近 7 天变化：\(changeText)；本周称重 \(weightDaysInLastSevenDays) 天
        今天称重：\(weighedToday ? "是" : "否")
        今天记录 \(todayMealCount) 餐，已分析 \(todayAnalyzedMealCount) 餐，\(caloriesText)
        已识别结构：\(groupText.isEmpty ? "无" : groupText)；饮食连续记录 \(mealRecordingStreak) 天
        昨日饮食：记录 \(previousDayMealCount) 餐、已分析 \(previousDayAnalyzedMealCount) 餐，\(previousCaloriesText)
        昨日餐盘结构：\(previousGroupText.isEmpty ? "无" : previousGroupText)
        昨日运动与昨夜睡眠：\(healthText)
        """
    }

    var hasPreviousDayReviewData: Bool {
        previousDayMealCount > 0 || previousDayHealth?.hasAnyData == true
    }
}

enum LocalCoachEngine {
    static func brief(for context: CoachContext) -> CoachBrief {
        let groups = Set(context.todayGroups)

        guard let currentWeight = context.currentWeight else {
            return CoachBrief(
                headline: "先建立你的体重基线",
                message: "完成第一次称重后，我才能把饮食记录和体重趋势放在一起看。",
                actionTitle: "记录体重",
                action: .weigh,
                symbol: "scalemass.fill",
                source: .localEngine
            )
        }

        if context.hour < 12, context.hasPreviousDayReviewData {
            if let sleepMinutes = context.previousDayHealth?.sleepMinutes, sleepMinutes < 360 {
                let sleepText = context.previousDayHealth?.sleepHoursText ?? "不足 6 小时"
                return CoachBrief(
                    headline: "昨夜恢复优先",
                    message: "昨夜睡眠约 \(sleepText)，昨日记录 \(context.previousDayMealCount) 餐。今天先保持正常三餐，把高强度运动换成轻松步行。",
                    actionTitle: "知道了",
                    action: .none,
                    symbol: "bed.double.fill",
                    source: .localEngine
                )
            }

            let steps = context.previousDayHealth?.steps ?? 0
            let exercise = context.previousDayHealth?.exerciseMinutes ?? 0
            if steps > 0, steps < 5_000, exercise < 20 {
                return CoachBrief(
                    headline: "今天补一点活动",
                    message: "昨日约 \(steps.formatted()) 步、锻炼 \(exercise) 分钟，饮食记录 \(context.previousDayMealCount) 餐。今天找一个饭后走 15 分钟即可。",
                    actionTitle: "知道了",
                    action: .none,
                    symbol: "figure.walk",
                    source: .localEngine
                )
            }

            if let health = context.previousDayHealth {
                return CoachBrief(
                    headline: "昨日节奏已整理",
                    message: "\(health.compactText)，饮食记录 \(context.previousDayMealCount) 餐。今天只延续一个做得最稳的小习惯。",
                    actionTitle: "查看趋势",
                    action: .viewProgress,
                    symbol: "sunrise.fill",
                    source: .localEngine
                )
            }
        }

        if !context.weighedToday, context.hour < 14 {
            return CoachBrief(
                headline: "今天先做一件小事",
                message: "站上体重秤即可，不必评价单次数字；连续数据比某一天的波动更有价值。",
                actionTitle: "去称重",
                action: .weigh,
                symbol: "figure.stand",
                source: .localEngine
            )
        }

        if context.todayMealCount == 0, context.hour >= 11 {
            return CoachBrief(
                headline: "别让今天的饮食变成盲区",
                message: "下一餐只要拍一张照片，我会自动整理食物结构和估算范围。",
                actionTitle: "记录下一餐",
                action: .logMeal,
                symbol: "camera.fill",
                source: .localEngine
            )
        }

        if context.todayAnalyzedMealCount < context.todayMealCount {
            return CoachBrief(
                headline: "照片还可以多给你一点反馈",
                message: "今天有未分析的饮食照片，补上 Vision 分析后再决定下一餐怎么搭配。",
                actionTitle: "查看饮食",
                action: .reviewMeals,
                symbol: "viewfinder",
                source: .localEngine
            )
        }

        if groups.contains(.fried) || groups.contains(.fastFood) || groups.contains(.dessert) {
            return CoachBrief(
                headline: "下一餐做一次温和补位",
                message: "今天已经有能量偏高的餐食；下一餐优先蔬菜、清淡蛋白质和无糖饮品，不需要用挨饿补偿。",
                actionTitle: "记录下一餐",
                action: .logMeal,
                symbol: "leaf.fill",
                source: .localEngine
            )
        }

        if context.todayMealCount >= 2, !groups.contains(.vegetable) {
            return CoachBrief(
                headline: "今天还差一块拼图",
                message: "已记录的餐食里还没识别到蔬菜；下一餐加一份即可，不需要重做整天计划。",
                actionTitle: "记录下一餐",
                action: .logMeal,
                symbol: "carrot.fill",
                source: .localEngine
            )
        }

        if currentWeight <= context.targetWeight {
            return CoachBrief(
                headline: "目标已到，开始守住节奏",
                message: "继续保持称重和拍照记录，把重点从追求更低数字转为稳定习惯。",
                actionTitle: "查看趋势",
                action: .viewProgress,
                symbol: "checkmark.seal.fill",
                source: .localEngine
            )
        }

        if let change = context.sevenDayChange, change > 0.6 {
            return CoachBrief(
                headline: "看七天，不审判今天",
                message: "近七天记录上升约 \(String(format: "%.1f", change)) kg。先保证接下来三天同一时段称重，再根据趋势调整餐盘。",
                actionTitle: "查看趋势",
                action: .viewProgress,
                symbol: "chart.xyaxis.line",
                source: .localEngine
            )
        }

        if context.weightDaysInLastSevenDays < 4 {
            return CoachBrief(
                headline: "你的下一步不是更严格，而是更连续",
                message: "本周称重 \(context.weightDaysInLastSevenDays) 天。先把固定时间称重做到四天，趋势才会更可靠。",
                actionTitle: "查看趋势",
                action: .viewProgress,
                symbol: "calendar.badge.checkmark",
                source: .localEngine
            )
        }

        let streakText = context.mealRecordingStreak > 0
            ? "饮食已经连续记录 \(context.mealRecordingStreak) 天"
            : "今天已经留下了有效记录"
        return CoachBrief(
            headline: "节奏正在形成",
            message: "\(streakText)。维持现在的记录密度，比临时加码更容易看见真实变化。",
            actionTitle: "查看进展",
            action: .viewProgress,
            symbol: "sparkles",
            source: .localEngine
        )
    }
}

@MainActor
final class OnDeviceAIManager: ObservableObject {
    enum State: Equatable {
        case checking
        case available
        case testing
        case verified(String)
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case requiresNewerSystem
        case frameworkUnavailable
        case testFailed

        var title: String {
            switch self {
            case .checking:
                return "正在检测端侧 AI"
            case .available:
                return "端侧模型已就绪"
            case .testing:
                return "正在运行本地测试"
            case .verified:
                return "端侧模型可以使用"
            case .appleIntelligenceNotEnabled:
                return "Apple 智能尚未开启"
            case .modelNotReady:
                return "系统模型尚未就绪"
            case .deviceNotEligible:
                return "当前条件不支持"
            case .requiresNewerSystem:
                return "需要 iOS 26 或更高版本"
            case .frameworkUnavailable:
                return "当前构建不含端侧模型框架"
            case .testFailed:
                return "端侧测试暂时失败"
            }
        }

        var detail: String {
            switch self {
            case .checking:
                return "正在读取这台设备的系统模型状态。"
            case .available:
                return "Apple 的本地语言模型可用，可以继续进行功能测试。"
            case .testing:
                return "正在手机本地生成一句测试回复，不会上传任何数据。"
            case .verified:
                return "已完成真实生成测试，后续可用于教练建议和周报表达。"
            case .appleIntelligenceNotEnabled:
                return "请在系统“Apple 智能与 Siri”中开启；若没有该入口，可能受设备或地区限制。"
            case .modelNotReady:
                return "连接无线局域网和电源，等待系统完成模型下载后再试。"
            case .deviceNotEligible:
                return "设备、账户地区或系统条件当前无法提供 Apple 端侧模型。"
            case .requiresNewerSystem:
                return "其他记录功能仍可正常使用，AI 教练将采用本地规则。"
            case .frameworkUnavailable:
                return "其他记录功能仍可正常使用，AI 教练将采用本地规则。"
            case .testFailed:
                return "系统报告模型可用，但本次生成没有成功，可以稍后重新检测。"
            }
        }

        var symbol: String {
            switch self {
            case .verified:
                return "checkmark.seal.fill"
            case .available:
                return "apple.intelligence"
            case .checking, .testing:
                return "sparkles"
            case .modelNotReady:
                return "arrow.down.circle.fill"
            case .appleIntelligenceNotEnabled:
                return "switch.2"
            case .deviceNotEligible, .requiresNewerSystem, .frameworkUnavailable, .testFailed:
                return "exclamationmark.triangle.fill"
            }
        }

        var testOutput: String? {
            guard case let .verified(output) = self else { return nil }
            return output
        }

        var isBusy: Bool {
            self == .checking || self == .testing
        }

        var isPositive: Bool {
            switch self {
            case .available, .verified:
                return true
            default:
                return false
            }
        }

        fileprivate var diagnosticCode: String {
            switch self {
            case .checking: return "checking"
            case .available: return "available"
            case .testing: return "testing"
            case .verified: return "verified"
            case .appleIntelligenceNotEnabled: return "apple_intelligence_not_enabled"
            case .modelNotReady: return "model_not_ready"
            case .deviceNotEligible: return "device_not_eligible"
            case .requiresNewerSystem: return "requires_ios_26"
            case .frameworkUnavailable: return "framework_unavailable"
            case .testFailed: return "test_failed"
            }
        }
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var diagnosticDetail: String?

    private var hasPerformedAutomaticCheck = false

    func detectAndTestIfNeeded() async {
        guard !hasPerformedAutomaticCheck else { return }
        hasPerformedAutomaticCheck = true
        await detectAndTest()
    }

    func detectAndTest() async {
        diagnosticDetail = nil
        updateState(.checking)

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            await inspectSystemModel()
        } else {
            updateState(.requiresNewerSystem)
        }
#else
        updateState(.frameworkUnavailable)
#endif
    }

    func coachBrief(for context: CoachContext) async -> CoachBrief {
        let fallback = LocalCoachEngine.brief(for: context)

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return fallback }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    你是轻衡 App 的减重陪伴教练。只使用简体中文。
                    你只能根据提供的数据和规则建议做温和改写，不新增事实，不诊断疾病，
                    不羞辱用户，不鼓励极端节食。回复只写一段，不超过 70 个汉字。
                    """
                )
                let response = try await session.respond(
                    to: """
                    用户数据：
                    \(context.promptDescription)

                    已由本地规则确定的建议：\(fallback.message)
                    请保持原意，改写得自然、具体、有陪伴感。只输出改写后的建议正文。
                    """
                )
                let text = sanitizedCoachResponse(response.content)
                if !text.isEmpty {
                    return fallback.replacingMessage(text, source: .appleFoundationModel)
                }
            } catch {
#if DEBUG
                print("[OnDeviceAI] coach generation failed: \(error)")
#endif
            }
        }
#endif

        return fallback
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func inspectSystemModel() async {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            updateState(.available)
            await runFunctionalTest(using: model)
        case .unavailable(.appleIntelligenceNotEnabled):
            updateState(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            updateState(.modelNotReady)
        case .unavailable(.deviceNotEligible):
            updateState(.deviceNotEligible)
        @unknown default:
            updateState(.deviceNotEligible)
        }
    }

    @available(iOS 26.0, *)
    private func runFunctionalTest(using model: SystemLanguageModel) async {
        updateState(.testing)

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: "你是轻衡 App 的端侧健康助手。只使用简体中文，并严格保持回复简短。"
            )
            let response = try await session.respond(to: "只回复这句话：端侧模型已连接")
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            updateState(.verified(output.isEmpty ? "端侧模型已返回响应" : String(output.prefix(60))))
        } catch {
            diagnosticDetail = String(describing: error)
            updateState(.testFailed)
        }
    }
#endif

    private func updateState(_ newState: State) {
        state = newState
        UserDefaults.standard.set(newState.diagnosticCode, forKey: "onDeviceAIStatus")
#if DEBUG
        print("[OnDeviceAI] status=\(newState.diagnosticCode)")
#endif
    }

    private func sanitizedCoachResponse(_ value: String) -> String {
        let compact = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"“”"))
        return String(compact.prefix(120))
    }
}

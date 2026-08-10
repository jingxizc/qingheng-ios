import Foundation

struct WeeklyCoachReport: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let currentWeight: Double?
    let weightChange: Double?
    let weightDays: Int
    let mealDays: Int
    let mealCount: Int
    let analyzedMealCount: Int
    let averageNutritionScore: Int?
    let headline: String
    let summary: String
    let win: String
    let focus: String
    let nextGoal: String

    var periodText: String {
        "\(startDate.formatted(.dateTime.month().day())) – \(endDate.formatted(.dateTime.month().day()))"
    }

    var weightChangeText: String {
        guard let weightChange else { return "数据不足" }
        return String(format: "%+.1f kg", weightChange)
    }

    var mealCoverageText: String {
        "\(mealDays) / 7 天"
    }

    var weightCoverageText: String {
        "\(weightDays) / 7 天"
    }

    func replacingNarrative(
        headline: String,
        summary: String,
        win: String,
        focus: String,
        nextGoal: String
    ) -> WeeklyCoachReport {
        func cleaned(_ value: String, fallback: String, limit: Int) -> String {
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? fallback : String(result.prefix(limit))
        }

        return WeeklyCoachReport(
            startDate: startDate,
            endDate: endDate,
            currentWeight: currentWeight,
            weightChange: weightChange,
            weightDays: weightDays,
            mealDays: mealDays,
            mealCount: mealCount,
            analyzedMealCount: analyzedMealCount,
            averageNutritionScore: averageNutritionScore,
            headline: cleaned(headline, fallback: self.headline, limit: 32),
            summary: cleaned(summary, fallback: self.summary, limit: 180),
            win: cleaned(win, fallback: self.win, limit: 180),
            focus: cleaned(focus, fallback: self.focus, limit: 180),
            nextGoal: cleaned(nextGoal, fallback: self.nextGoal, limit: 120)
        )
    }
}

enum WeeklyCoachEngine {
    static func makeReport(
        weights: [WeightRecord],
        meals: [MealRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyCoachReport {
        let endDate = now
        let today = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        let weeklyWeights = weights
            .filter { $0.measuredAt >= startDate && $0.measuredAt <= now }
            .sorted { $0.measuredAt < $1.measuredAt }
        let weeklyMeals = meals
            .filter { $0.eatenAt >= startDate && $0.eatenAt <= now }
            .sorted { $0.eatenAt < $1.eatenAt }

        let weightDays = Set(weeklyWeights.map { calendar.startOfDay(for: $0.measuredAt) }).count
        let mealDays = Set(weeklyMeals.map { calendar.startOfDay(for: $0.eatenAt) }).count
        let currentWeight = weeklyWeights.last?.weightKg
        let weightChange: Double?
        if let first = weeklyWeights.first, let last = weeklyWeights.last, weeklyWeights.count > 1 {
            weightChange = last.weightKg - first.weightKg
        } else {
            weightChange = nil
        }

        let analyzedMeals = weeklyMeals.filter(\.hasAnalysis)
        let scores = analyzedMeals.compactMap(\.nutritionScore)
        let averageScore = scores.isEmpty
            ? nil
            : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        let groups = Set(analyzedMeals.flatMap(\.analysisGroups))

        let headline: String
        if weeklyWeights.isEmpty && weeklyMeals.isEmpty {
            headline = "从一条真实记录开始"
        } else if weightDays >= 4 && mealDays >= 4 {
            headline = "这一周的节奏看得见"
        } else {
            headline = "先补齐趋势，不急着加码"
        }

        let summary = summaryText(
            weightDays: weightDays,
            mealDays: mealDays,
            mealCount: weeklyMeals.count,
            weightChange: weightChange
        )
        let win = winText(
            weightDays: weightDays,
            mealDays: mealDays,
            mealCount: weeklyMeals.count,
            weightChange: weightChange
        )
        let focusAndGoal = focusAndGoal(
            weightDays: weightDays,
            mealDays: mealDays,
            mealCount: weeklyMeals.count,
            analyzedMealCount: analyzedMeals.count,
            averageScore: averageScore,
            groups: groups,
            weightChange: weightChange
        )

        return WeeklyCoachReport(
            startDate: startDate,
            endDate: endDate,
            currentWeight: currentWeight,
            weightChange: weightChange,
            weightDays: weightDays,
            mealDays: mealDays,
            mealCount: weeklyMeals.count,
            analyzedMealCount: analyzedMeals.count,
            averageNutritionScore: averageScore,
            headline: headline,
            summary: summary,
            win: win,
            focus: focusAndGoal.focus,
            nextGoal: focusAndGoal.goal
        )
    }

    private static func summaryText(
        weightDays: Int,
        mealDays: Int,
        mealCount: Int,
        weightChange: Double?
    ) -> String {
        var parts = ["称重 \(weightDays) 天", "饮食记录 \(mealDays) 天、\(mealCount) 餐"]
        if let weightChange {
            parts.append("体重趋势 \(String(format: "%+.1f kg", weightChange))")
        }
        return parts.joined(separator: " · ")
    }

    private static func winText(
        weightDays: Int,
        mealDays: Int,
        mealCount: Int,
        weightChange: Double?
    ) -> String {
        if mealDays >= 5 {
            return "你有 \(mealDays) 天留下了饮食照片。真实记录比追求完美更能帮你发现规律。"
        }
        if weightDays >= 4 {
            return "你完成了 \(weightDays) 天称重，已经有足够样本开始看趋势，而不是被单次数字牵着走。"
        }
        if let weightChange, weightChange < -0.2 {
            return "记录中的七日趋势下降 \(String(format: "%.1f", abs(weightChange))) kg；保持现在的节奏即可，不需要临时加码。"
        }
        if mealCount > 0 || weightDays > 0 {
            return "你已经留下了这周的第一批真实数据。愿意记录，本身就是让计划变得可调整的一步。"
        }
        return "这一周暂时没有记录。它不是失败，只说明下周最有效的起点很明确。"
    }

    private static func focusAndGoal(
        weightDays: Int,
        mealDays: Int,
        mealCount: Int,
        analyzedMealCount: Int,
        averageScore: Int?,
        groups: Set<FoodGroup>,
        weightChange: Double?
    ) -> (focus: String, goal: String) {
        if weightDays < 4 {
            return (
                "称重样本还不足以判断真实方向，先不根据一两次波动调整吃法。",
                "下周在相近时段完成至少 4 天称重。"
            )
        }
        if mealDays < 4 {
            return (
                "饮食记录还有较多空白，教练暂时看不到哪些场景最容易偏离计划。",
                "下周至少 4 天拍下最容易忘记的那一餐。"
            )
        }
        if mealCount > 0, analyzedMealCount < mealCount {
            return (
                "有些照片还没有形成可用的餐盘结构，周趋势会因此少一块信息。",
                "下周把未分析或不准确的照片及时确认。"
            )
        }
        if !groups.contains(.vegetable) {
            return (
                "本周已确认的餐食里还没有形成稳定的蔬菜记录。",
                "下周每天选一餐，补一份看得见的蔬菜。"
            )
        }
        if let averageScore, averageScore < 60 {
            return (
                "本周餐盘结构仍有温和优化空间，重点是补位，不是用挨饿抵消。",
                "下一餐优先蔬菜、清淡蛋白质和无糖饮品。"
            )
        }
        if let weightChange, weightChange > 0.6 {
            return (
                "七日记录有上升，但仍要先排除称重时段与水分波动的影响。",
                "继续固定时段称重 4 天，再根据下一份周报决定是否调整。"
            )
        }
        return (
            "目前最值得保护的是连续性，不需要为了更快而同时增加很多规则。",
            "下周保持当前记录频率，只专注完成每天的一小步。"
        )
    }
}

import Foundation
import XCTest
@testable import Diet

final class WeightAnalyticsTests: XCTestCase {
    func testGoalProgressIsClamped() {
        XCTAssertEqual(
            WeightAnalytics.progress(start: 80, current: 70, target: 60),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeightAnalytics.progress(start: 80, current: 55, target: 60),
            1,
            accuracy: 0.001
        )
    }

    func testWeightSessionUsesMedianAndRejectsOutlier() {
        let aggregate = WeightSessionPolicy.aggregate([70.0, 70.1, 70.7, 70.05])

        XCTAssertEqual(aggregate.representativeWeight, 70.05, accuracy: 0.001)
        XCTAssertEqual(aggregate.acceptedReadings.count, 3)
        XCTAssertEqual(aggregate.rejectedCount, 1)
    }

    func testWeightSessionOnlyMergesNearbyReadingsWithinFiveMinutes() {
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            WeightSessionPolicy.canMerge(
                existingWeight: 70,
                lastUpdatedAt: start,
                existingDeviceName: "MI SCALE2",
                newWeight: 70.25,
                newDate: start.addingTimeInterval(299),
                newDeviceName: "MI SCALE2"
            )
        )
        XCTAssertFalse(
            WeightSessionPolicy.canMerge(
                existingWeight: 70,
                lastUpdatedAt: start,
                existingDeviceName: "MI SCALE2",
                newWeight: 70.2,
                newDate: start.addingTimeInterval(301),
                newDeviceName: "MI SCALE2"
            )
        )
        XCTAssertFalse(
            WeightSessionPolicy.canMerge(
                existingWeight: 70,
                lastUpdatedAt: start,
                existingDeviceName: "MI SCALE2",
                newWeight: 71,
                newDate: start.addingTimeInterval(60),
                newDeviceName: "MI SCALE2"
            )
        )
    }

    func testPersonalWeightPolicyRejectsAnotherPersonsWeight() {
        let now = Date(timeIntervalSince1970: 10_000)
        let records = [
            WeightRecord(weightKg: 72.4, measuredAt: now.addingTimeInterval(-2_000)),
            WeightRecord(weightKg: 73.1, measuredAt: now.addingTimeInterval(-1_000)),
            WeightRecord(weightKg: 72.8, measuredAt: now.addingTimeInterval(-500))
        ]

        let suspicious = PersonalWeightPolicy.assess(
            newWeightKg: 48.7,
            measuredAt: now,
            against: records
        )
        let normal = PersonalWeightPolicy.assess(
            newWeightKg: 73.4,
            measuredAt: now,
            against: records
        )

        XCTAssertFalse(suspicious.isPlausible)
        XCTAssertTrue(normal.isPlausible)
        XCTAssertEqual(suspicious.referenceWeightKg ?? 0, 72.8, accuracy: 0.001)
    }

    func testManualWeightCanEstablishANewPersonalBaseline() {
        let now = Date(timeIntervalSince1970: 20_000)
        let records = [
            WeightRecord(weightKg: 99, measuredAt: now.addingTimeInterval(-3_000)),
            WeightRecord(
                weightKg: 72,
                measuredAt: now.addingTimeInterval(-1_000),
                source: .manual
            )
        ]

        let assessment = PersonalWeightPolicy.assess(
            newWeightKg: 72.4,
            measuredAt: now,
            against: records
        )

        XCTAssertTrue(assessment.isPlausible)
        XCTAssertEqual(assessment.referenceWeightKg, 72)
    }

    func testVisionFoodKnowledgeBuildsBalancedMealEstimate() throws {
        let analysis = FoodKnowledgeBase.analyze(
            observations: [
                FoodVisionObservation(identifier: "steamed rice", confidence: 0.88),
                FoodVisionObservation(identifier: "grilled chicken", confidence: 0.82),
                FoodVisionObservation(identifier: "broccoli", confidence: 0.71)
            ]
        )

        XCTAssertTrue(analysis.isRecognized)
        XCTAssertTrue(analysis.tags.contains("米饭"))
        XCTAssertTrue(analysis.tags.contains("禽肉"))
        XCTAssertTrue(analysis.tags.contains("蔬菜"))
        XCTAssertGreaterThanOrEqual(analysis.nutritionScore ?? 0, 80)

        let range = try XCTUnwrap(analysis.calorieRange(for: .regular))
        XCTAssertLessThan(range.lowerBound, range.upperBound)
    }

    func testVisionPortionChangesCalorieRange() throws {
        let analysis = FoodKnowledgeBase.analyze(
            observations: [
                FoodVisionObservation(identifier: "pizza, pizza pie", confidence: 0.94)
            ]
        )

        let small = try XCTUnwrap(analysis.calorieRange(for: .small))
        let large = try XCTUnwrap(analysis.calorieRange(for: .large))
        XCTAssertLessThan(small.upperBound, large.upperBound)
    }

    func testLocalCoachProvidesConcreteFallbackWithoutAppleIntelligence() {
        let context = CoachContext(
            currentWeight: 72,
            targetWeight: 65,
            sevenDayChange: nil,
            weighedToday: false,
            todayMealCount: 0,
            todayAnalyzedMealCount: 0,
            todayCaloriesLow: nil,
            todayCaloriesHigh: nil,
            todayGroups: [],
            mealRecordingStreak: 0,
            weightDaysInLastSevenDays: 1,
            hour: 9,
            previousDay: nil,
            previousDayMealCount: 0,
            previousDayAnalyzedMealCount: 0,
            previousDayCaloriesLow: nil,
            previousDayCaloriesHigh: nil,
            previousDayGroups: [],
            previousDayHealth: nil
        )

        let brief = LocalCoachEngine.brief(for: context)
        XCTAssertEqual(brief.action, .weigh)
        XCTAssertFalse(brief.message.isEmpty)
        XCTAssertEqual(brief.source, .localEngine)
    }

    func testMealCorrectionUpdatesAnalysisAndScore() {
        let analysis = FoodVisionAnalysis(
            tags: ["披萨"],
            groups: [.fastFood],
            mediumCaloriesLow: 600,
            mediumCaloriesHigh: 1_000,
            nutritionScore: 37,
            summary: "原始结果",
            confidence: 0.4,
            rawLabels: []
        )
        let meal = MealRecord(mealType: .dinner, analysis: analysis)

        meal.applyCorrection(
            tags: ["米饭", "青菜", "鸡蛋"],
            groups: [.carbohydrate, .vegetable, .protein],
            portion: .regular,
            caloriesLow: 420,
            caloriesHigh: 620
        )

        XCTAssertTrue(meal.isUserCorrected)
        XCTAssertEqual(meal.correctionCount, 1)
        XCTAssertEqual(meal.calorieRangeText, "420–620 千卡")
        XCTAssertGreaterThanOrEqual(meal.nutritionScore ?? 0, 80)
        XCTAssertTrue(meal.analysisSummary.contains("已按你的确认更新"))
    }

    func testWeeklyCoachBuildsSevenDayCoverageAndSingleGoal() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weights = [
            WeightRecord(weightKg: 70, measuredAt: now.addingTimeInterval(-2 * 86_400)),
            WeightRecord(weightKg: 69.5, measuredAt: now)
        ]
        let meals = [
            MealRecord(eatenAt: now.addingTimeInterval(-86_400), mealType: .dinner),
            MealRecord(eatenAt: now, mealType: .lunch)
        ]

        let report = WeeklyCoachEngine.makeReport(
            weights: weights,
            meals: meals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(report.weightDays, 2)
        XCTAssertEqual(report.mealDays, 2)
        XCTAssertEqual(try XCTUnwrap(report.weightChange), -0.5, accuracy: 0.001)
        XCTAssertTrue(report.nextGoal.contains("至少 4 天称重"))
        XCTAssertFalse(report.win.isEmpty)
    }

    func testQwenQRCodeConfigurationDecodesAndBuildsWorkspaceEndpoint() throws {
        let payload = """
        {"v":1,"provider":"dashscope","region":"cn-beijing","workspace_id":"ws-test_01","api_key":"sk-test-secret"}
        """

        let configuration = try QwenConfiguration.decodeQRCodePayload(payload)

        XCTAssertEqual(configuration.workspaceID, "ws-test_01")
        XCTAssertEqual(
            configuration.endpointURL?.absoluteString,
            "https://ws-test_01.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
        XCTAssertEqual(configuration.connectionScope, "业务空间 ••••est_01")
    }

    func testQwenQRCodeConfigurationUsesPublicPayAsYouGoEndpointWithoutWorkspace() throws {
        let payload = """
        {"v":2,"provider":"dashscope","region":"cn-beijing","api_key":"sk-test-secret"}
        """

        let configuration = try QwenConfiguration.decodeQRCodePayload(payload)

        XCTAssertNil(configuration.workspaceID)
        XCTAssertEqual(
            configuration.endpointURL?.absoluteString,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
        XCTAssertEqual(configuration.connectionScope, "按量付费公共接口")
    }

    func testQwenQRCodeConfigurationRejectsUnsupportedProvider() {
        let payload = """
        {"v":1,"provider":"other","region":"cn-beijing","workspace_id":"ws-test","api_key":"sk-test-secret"}
        """

        XCTAssertThrowsError(try QwenConfiguration.decodeQRCodePayload(payload)) { error in
            guard case QwenConfiguration.ConfigurationError.unsupportedProvider = error else {
                return XCTFail("应拒绝不支持的 AI 服务商，实际错误：\(error)")
            }
        }
    }

    func testQwenMealPayloadCreatesPortionAwareAnalysis() throws {
        let payload = QwenMealPayload(
            foods: [
                .init(name: "米饭", group: "carbohydrate", caloriesLow: 180, caloriesHigh: 240),
                .init(name: "番茄炒蛋", group: "protein", caloriesLow: 220, caloriesHigh: 320),
                .init(name: "西兰花", group: "vegetable", caloriesLow: 40, caloriesHigh: 70)
            ],
            totalCaloriesLow: 440,
            totalCaloriesHigh: 630,
            nutritionScore: 84,
            summary: "主食、蛋白质和蔬菜搭配较完整。",
            confidence: 82,
            uncertainties: ["烹调油用量不可见"]
        )

        let analysis = try payload.makeAnalysis(portion: .large)
        let estimatedRange = try XCTUnwrap(analysis.calorieRange(for: .large))

        XCTAssertEqual(analysis.tags, ["米饭", "番茄炒蛋", "西兰花"])
        XCTAssertEqual(analysis.groups, [.carbohydrate, .protein, .vegetable])
        XCTAssertEqual(estimatedRange.lowerBound, 440)
        XCTAssertEqual(estimatedRange.upperBound, 630)
        XCTAssertEqual(analysis.confidence, 0.82, accuracy: 0.001)
        XCTAssertTrue(analysis.summary.contains("烹调油用量不可见"))
    }

    func testQwenRefinementBuildsBoundedResultWithoutChangingConfirmedFoods() throws {
        let payload = QwenMealRefinementPayload(
            totalCaloriesLow: 460,
            totalCaloriesHigh: 650,
            nutritionScore: 86,
            summary: "按确认后的食物重新估算，餐盘结构较完整。",
            confidence: 78,
            uncertainties: ["烹调油用量不可见"]
        )

        let result = try payload.makeResult(fallbackScore: 72)

        XCTAssertEqual(result.caloriesLow, 460)
        XCTAssertEqual(result.caloriesHigh, 650)
        XCTAssertEqual(result.nutritionScore, 86)
        XCTAssertEqual(result.confidence, 0.78, accuracy: 0.001)
        XCTAssertTrue(result.summary.contains("烹调油用量不可见"))
    }

    func testMealCorrectionKeepsUserFactsAndUsesQwenRefinementNarrative() {
        let initial = FoodVisionAnalysis(
            tags: ["披萨"],
            groups: [.fastFood],
            mediumCaloriesLow: 700,
            mediumCaloriesHigh: 1_000,
            nutritionScore: 35,
            summary: "初次识别结果",
            confidence: 0.4,
            rawLabels: ["pizza"]
        )
        let meal = MealRecord(mealType: .lunch, analysis: initial)
        let refinement = MealRefinementResult(
            caloriesLow: 430,
            caloriesHigh: 610,
            nutritionScore: 88,
            summary: "用户确认后，主食、蛋白质和蔬菜搭配较完整。",
            confidence: 0.83
        )

        meal.applyCorrection(
            tags: ["米饭", "鸡蛋", "青菜"],
            groups: [.carbohydrate, .protein, .vegetable],
            portion: .regular,
            caloriesLow: refinement.caloriesLow,
            caloriesHigh: refinement.caloriesHigh,
            refinement: refinement
        )

        XCTAssertEqual(meal.analysisTags, ["米饭", "鸡蛋", "青菜"])
        XCTAssertEqual(meal.analysisGroups, [.carbohydrate, .protein, .vegetable])
        XCTAssertEqual(meal.calorieRangeText, "430–610 千卡")
        XCTAssertEqual(meal.nutritionScore, 88)
        XCTAssertEqual(meal.analysisSummary, refinement.summary)
        XCTAssertEqual(meal.analysisConfidence, 0.83)
        XCTAssertTrue(meal.isUserCorrected)
    }

    func testSleepIntervalsAreMergedWithoutDoubleCountingOverlaps() {
        let start = Date(timeIntervalSince1970: 10_000)
        let minutes = HealthKitManager.mergedMinutes([
            DateInterval(start: start, duration: 120 * 60),
            DateInterval(start: start.addingTimeInterval(60 * 60), duration: 120 * 60),
            DateInterval(start: start.addingTimeInterval(240 * 60), duration: 60 * 60)
        ])

        XCTAssertEqual(minutes, 240)
    }

    func testMorningCoachCombinesPreviousActivitySleepAndMeals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_035_200)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let meal = MealRecord(eatenAt: yesterday, mealType: .dinner)
        meal.applyCorrection(
            tags: ["米饭", "青菜"],
            groups: [.carbohydrate, .vegetable],
            portion: .regular,
            caloriesLow: 420,
            caloriesHigh: 560
        )
        let health = DailyHealthSummary(
            day: calendar.startOfDay(for: yesterday),
            steps: 3_200,
            activeEnergyKcal: 180,
            exerciseMinutes: 8,
            sleepMinutes: 420
        )
        let context = CoachContext.make(
            weights: [WeightRecord(weightKg: 72, measuredAt: yesterday)],
            meals: [meal],
            targetWeight: 65,
            previousDayHealth: health,
            now: now,
            calendar: calendar
        )

        let brief = LocalCoachEngine.brief(for: context)

        XCTAssertEqual(context.previousDayMealCount, 1)
        XCTAssertEqual(context.previousDayCaloriesLow, 420)
        XCTAssertTrue(context.promptDescription.contains("3,200 步"))
        XCTAssertTrue(context.promptDescription.contains("睡眠 7 小时"))
        XCTAssertTrue(brief.message.contains("3,200"))
        XCTAssertTrue(brief.message.contains("8 分钟"))
    }

    func testNextMorningReminderNeverSchedulesInThePast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 7,
            minute: 30
        )))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 21
        )))

        let todayReminder = CoachNotificationManager.nextReminderDate(
            hour: 8,
            minute: 0,
            now: morning,
            calendar: calendar
        )
        let tomorrowReminder = CoachNotificationManager.nextReminderDate(
            hour: 8,
            minute: 0,
            now: evening,
            calendar: calendar
        )

        XCTAssertTrue(calendar.isDate(todayReminder, inSameDayAs: morning))
        XCTAssertFalse(calendar.isDate(tomorrowReminder, inSameDayAs: evening))
        XCTAssertGreaterThan(todayReminder, morning)
        XCTAssertGreaterThan(tomorrowReminder, evening)
    }
}

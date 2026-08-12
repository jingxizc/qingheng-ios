import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var scaleManager: BluetoothScaleManager
    @EnvironmentObject private var aiManager: OnDeviceAIManager
    @EnvironmentObject private var qwenAIService: QwenAIService
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var coachNotificationManager: CoachNotificationManager
    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var weights: [WeightRecord]
    @Query(sort: \MealRecord.eatenAt, order: .reverse)
    private var meals: [MealRecord]

    @AppStorage("autoBluetoothSync") private var autoBluetoothSync = true
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = false
    @AppStorage("targetWeight") private var targetWeight = 65.0
    @AppStorage("coachRemindersEnabled") private var coachRemindersEnabled = false
    @AppStorage("coachReminderHour") private var coachReminderHour = 8
    @AppStorage("coachReminderMinute") private var coachReminderMinute = 0
    @AppStorage("morningCoachMigrationVersion") private var morningCoachMigrationVersion = 0
    @State private var selectedTab = 0
    @State private var syncToast: String?
    @State private var syncToastSymbol = "checkmark.circle.fill"

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tag(0)
                .tabItem { Label("今天", systemImage: "sparkles") }

            MealsView()
                .tag(1)
                .tabItem { Label("饮食", systemImage: "camera.fill") }

            ProgressView()
                .tag(2)
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tag(3)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(AppTheme.ink)
        .overlay(alignment: .top) {
            if let syncToast {
                Label(syncToast, systemImage: syncToastSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(AppTheme.ink.opacity(0.94), in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            migrateReminderTimeIfNeeded()
            if autoBluetoothSync {
                scaleManager.startMonitoring()
            }
        }
        .task {
            await aiManager.detectAndTestIfNeeded()
        }
        .task {
            await qwenAIService.refreshConnectionIfConfigured()
        }
        .task {
            guard healthKitManager.wellnessReadEnabled else { return }
            healthKitManager.startWellnessBackgroundDelivery()
            await healthKitManager.refreshPreviousDaySummary()
        }
        .task(id: reminderScheduleKey) {
            guard coachRemindersEnabled else {
                coachNotificationManager.removeScheduledReminders()
                return
            }
            let calendar = Calendar.current
            let reminderNow = Date.now
            let reminderDate = CoachNotificationManager.nextReminderDate(
                hour: coachReminderHour,
                minute: coachReminderMinute,
                now: reminderNow,
                calendar: calendar
            )
            let reviewDay = calendar.date(byAdding: .day, value: -1, to: reminderDate)
                ?? reminderDate
            let healthSummary: DailyHealthSummary?
            if healthKitManager.wellnessReadEnabled {
                healthSummary = try? await healthKitManager.dailySummary(
                    for: reviewDay,
                    calendar: calendar
                )
            } else {
                healthSummary = nil
            }
            let context = CoachContext.make(
                weights: weights,
                meals: meals,
                targetWeight: targetWeight,
                previousDayHealth: healthSummary,
                now: reminderDate,
                calendar: calendar
            )
            let fallback = LocalCoachEngine.brief(for: context)
            let morningBrief: CoachBrief
            if let cloudBrief = await qwenAIService.coachBrief(for: context, fallback: fallback) {
                morningBrief = cloudBrief
            } else {
                morningBrief = await aiManager.coachBrief(for: context)
            }
            await coachNotificationManager.updateSchedule(
                morningBrief: morningBrief,
                enabled: coachRemindersEnabled,
                hour: coachReminderHour,
                minute: coachReminderMinute,
                now: reminderNow,
                calendar: calendar
            )
        }
        .onChange(of: autoBluetoothSync) { _, enabled in
            enabled ? scaleManager.startMonitoring() : scaleManager.stopMonitoring()
        }
        .onChange(of: scaleManager.latestMeasurement?.id) { _, _ in
            guard let measurement = scaleManager.latestMeasurement else { return }
            save(measurement)
        }
    }

    private func save(_ measurement: ScaleMeasurement) {
        let assessment = PersonalWeightPolicy.assess(
            newWeightKg: measurement.weightKg,
            measuredAt: measurement.measuredAt,
            against: weights
        )
        guard assessment.isPlausible else {
            let referenceText = assessment.referenceWeightKg.map {
                String(format: "（近期约 %.1f kg）", $0)
            } ?? ""
            showSyncToast(
                String(format: "已拦截异常读数 %.1f kg", measurement.weightKg) + referenceText,
                symbol: "exclamationmark.shield.fill"
            )
            return
        }

        if let session = weights.first(where: { record in
            record.source == .bluetooth
                && WeightSessionPolicy.canMerge(
                    existingWeight: record.weightKg,
                    lastUpdatedAt: record.sessionUpdatedAt ?? record.measuredAt,
                    existingDeviceName: record.deviceName,
                    newWeight: measurement.weightKg,
                    newDate: measurement.measuredAt,
                    newDeviceName: measurement.deviceName
                )
        }) {
            let result = session.mergeBluetoothMeasurement(
                weightKg: measurement.weightKg,
                measuredAt: measurement.measuredAt
            )
            try? modelContext.save()

            if healthKitSyncEnabled {
                Task { await healthKitManager.saveWeight(session) }
            }

            showSyncToast(
                String(
                    format: "已合并 %d 次读数：%.1f kg",
                    result.allReadings.count,
                    result.representativeWeight
                )
            )
            return
        }

        let record = WeightRecord(
            weightKg: measurement.weightKg,
            measuredAt: measurement.measuredAt,
            source: .bluetooth,
            deviceName: measurement.deviceName
        )
        modelContext.insert(record)
        try? modelContext.save()

        if healthKitSyncEnabled {
            Task {
                await healthKitManager.saveWeight(record)
            }
        }

        showSyncToast(String(format: "已记录 %.1f kg", measurement.weightKg))
    }

    private func showSyncToast(
        _ message: String,
        symbol: String = "checkmark.circle.fill"
    ) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            syncToast = message
            syncToastSymbol = symbol
        }
        UINotificationFeedbackGenerator().notificationOccurred(
            symbol == "checkmark.circle.fill" ? .success : .warning
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation { syncToast = nil }
        }
    }

    private var reminderScheduleKey: String {
        let weightState = weights
            .map { "\($0.id.uuidString):\($0.healthSyncVersion)" }
            .joined(separator: ",")
        let mealState = meals
            .map { "\($0.id.uuidString):\($0.analysisVersion)" }
            .joined(separator: ",")
        return "\(coachRemindersEnabled)-\(coachReminderHour)-\(coachReminderMinute)-\(targetWeight)-\(weightState)-\(mealState)-\(healthKitManager.healthDataRevision)-\(qwenAIService.isCloudReady)"
    }

    private func migrateReminderTimeIfNeeded() {
        guard morningCoachMigrationVersion < 1 else { return }
        if coachReminderHour == 20, coachReminderMinute == 30 {
            coachReminderHour = 8
            coachReminderMinute = 0
        }
        morningCoachMigrationVersion = 1
    }
}

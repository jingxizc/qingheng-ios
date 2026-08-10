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
    @AppStorage("coachReminderHour") private var coachReminderHour = 20
    @AppStorage("coachReminderMinute") private var coachReminderMinute = 30
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
        .task(id: reminderScheduleKey) {
            let reminderNow = Calendar.current.date(
                bySettingHour: coachReminderHour,
                minute: coachReminderMinute,
                second: 0,
                of: .now
            ) ?? .now
            await coachNotificationManager.updateSchedule(
                context: CoachContext.make(
                    weights: weights,
                    meals: meals,
                    targetWeight: targetWeight,
                    now: reminderNow
                ),
                weeklyReport: WeeklyCoachEngine.makeReport(weights: weights, meals: meals),
                enabled: coachRemindersEnabled,
                hour: coachReminderHour,
                minute: coachReminderMinute
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
        return "\(coachRemindersEnabled)-\(coachReminderHour)-\(coachReminderMinute)-\(targetWeight)-\(weightState)-\(mealState)"
    }
}

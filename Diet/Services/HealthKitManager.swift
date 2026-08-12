import Combine
import Foundation
import HealthKit

struct DailyHealthSummary: Equatable, Sendable {
    let day: Date
    let steps: Int?
    let activeEnergyKcal: Int?
    let exerciseMinutes: Int?
    let sleepMinutes: Int?

    var hasAnyData: Bool {
        steps != nil || activeEnergyKcal != nil || exerciseMinutes != nil || sleepMinutes != nil
    }

    var sleepHoursText: String? {
        guard let sleepMinutes else { return nil }
        let hours = sleepMinutes / 60
        let minutes = sleepMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }

    var compactText: String {
        var parts: [String] = []
        if let steps { parts.append("\(steps.formatted()) 步") }
        if let activeEnergyKcal { parts.append("活动 \(activeEnergyKcal) 千卡") }
        if let exerciseMinutes { parts.append("锻炼 \(exerciseMinutes) 分钟") }
        if let sleepHoursText { parts.append("睡眠 \(sleepHoursText)") }
        return parts.isEmpty ? "Apple 健康暂无可用记录" : parts.joined(separator: " · ")
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    enum State: Equatable {
        case unavailable
        case notDetermined
        case requesting
        case authorized
        case denied
        case failed

        var title: String {
            switch self {
            case .unavailable:
                return "Apple 健康不可用"
            case .notDetermined:
                return "尚未连接 Apple 健康"
            case .requesting:
                return "正在请求授权"
            case .authorized:
                return "已连接 Apple 健康"
            case .denied:
                return "体重写入权限未开启"
            case .failed:
                return "Apple 健康同步异常"
            }
        }

        var detail: String {
            switch self {
            case .unavailable:
                return "当前设备无法使用 HealthKit，轻衡中的记录不会受到影响。"
            case .notDetermined:
                return "开启后，新记录的体重会自动出现在系统“健康”App 中。"
            case .requesting:
                return "请在系统授权页允许轻衡写入体重。"
            case .authorized:
                return "体重写入已就绪；运动和睡眠仅在你单独允许后用于生成晨报。"
            case .denied:
                return "可以前往系统健康权限设置，允许轻衡写入体重后再试。"
            case .failed:
                return "本次操作未完成，可以稍后重新尝试。"
            }
        }

        var symbol: String {
            switch self {
            case .authorized:
                return "heart.circle.fill"
            case .requesting:
                return "heart.fill"
            case .notDetermined:
                return "heart.text.clipboard"
            case .unavailable, .denied, .failed:
                return "heart.slash.fill"
            }
        }

        var isPositive: Bool { self == .authorized }
        var isBusy: Bool { self == .requesting }
    }

    @Published private(set) var state: State = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var latestDailySummary: DailyHealthSummary?
    @Published private(set) var healthDataRevision = 0
    @Published private(set) var wellnessReadEnabled: Bool

    private let healthStore = HKHealthStore()
    private let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseTimeType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private var observerQueries: [HKObserverQuery] = []
    private static let wellnessReadKey = "healthWellnessReadEnabled"

    init() {
        wellnessReadEnabled = UserDefaults.standard.bool(forKey: Self.wellnessReadKey)
        refreshAuthorizationStatus()
        if wellnessReadEnabled {
            startWellnessBackgroundDelivery()
            Task { await refreshPreviousDaySummary() }
        }
    }

    func refreshAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        switch healthStore.authorizationStatus(for: bodyMassType) {
        case .notDetermined:
            state = .notDetermined
        case .sharingDenied:
            state = .denied
        case .sharingAuthorized:
            state = .authorized
        @unknown default:
            state = .failed
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return false
        }

        state = .requesting
        lastMessage = nil

        do {
            try await healthStore.requestAuthorization(
                toShare: [bodyMassType],
                read: []
            )
            refreshAuthorizationStatus()
            return state == .authorized
        } catch {
            lastMessage = "授权失败：\(error.localizedDescription)"
            state = .failed
            return false
        }
    }

    @discardableResult
    func requestWellnessAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return false
        }

        state = .requesting
        lastMessage = nil
        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: wellnessReadTypes
            )
            wellnessReadEnabled = true
            UserDefaults.standard.set(true, forKey: Self.wellnessReadKey)
            refreshAuthorizationStatus()
            await refreshPreviousDaySummary()
            startWellnessBackgroundDelivery()
            return true
        } catch {
            lastMessage = "健康数据授权失败：\(error.localizedDescription)"
            state = .failed
            return false
        }
    }

    func disableWellnessReading() {
        wellnessReadEnabled = false
        UserDefaults.standard.set(false, forKey: Self.wellnessReadKey)
        observerQueries.forEach(healthStore.stop)
        observerQueries.removeAll()
        latestDailySummary = nil
        healthDataRevision += 1
    }

    func startWellnessBackgroundDelivery() {
        guard wellnessReadEnabled, observerQueries.isEmpty else { return }

        for type in wellnessReadTypes.compactMap({ $0 as? HKSampleType }) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    await self.refreshPreviousDaySummary()
                    completion()
                }
            }
            observerQueries.append(query)
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .daily) { _, _ in }
        }
    }

    func refreshPreviousDaySummary(
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        guard wellnessReadEnabled else {
            latestDailySummary = nil
            return
        }
        let today = calendar.startOfDay(for: now)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        do {
            latestDailySummary = try await dailySummary(for: previousDay, calendar: calendar)
            healthDataRevision += 1
        } catch {
            lastMessage = "暂时无法读取运动或睡眠摘要：\(error.localizedDescription)"
        }
    }

    func dailySummary(
        for day: Date,
        calendar: Calendar = .current
    ) async throws -> DailyHealthSummary {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let sleepStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start) ?? start
        let sleepEndDay = calendar.date(byAdding: .day, value: 1, to: start) ?? end
        let sleepEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: sleepEndDay)
            ?? sleepEndDay.addingTimeInterval(43_200)

        async let stepValue = cumulativeSum(
            type: stepType,
            start: start,
            end: end,
            unit: .count()
        )
        async let energyValue = cumulativeSum(
            type: activeEnergyType,
            start: start,
            end: end,
            unit: .kilocalorie()
        )
        async let exerciseValue = cumulativeSum(
            type: exerciseTimeType,
            start: start,
            end: end,
            unit: .minute()
        )
        async let sleepValue = asleepMinutes(start: sleepStart, end: sleepEnd)

        let (steps, energy, exercise, sleep) = try await (
            stepValue,
            energyValue,
            exerciseValue,
            sleepValue
        )
        return DailyHealthSummary(
            day: start,
            steps: roundedPositive(steps),
            activeEnergyKcal: roundedPositive(energy),
            exerciseMinutes: roundedPositive(exercise),
            sleepMinutes: sleep > 0 ? sleep : nil
        )
    }

    @discardableResult
    func saveWeight(_ record: WeightRecord) async -> Bool {
        refreshAuthorizationStatus()
        guard state == .authorized else { return false }

        do {
            try await healthStore.save(makeSample(from: record))
            return true
        } catch {
            lastMessage = "体重未同步：\(error.localizedDescription)"
            return false
        }
    }

    func syncExistingWeights(_ records: [WeightRecord]) async {
        refreshAuthorizationStatus()
        guard state == .authorized else {
            lastMessage = "请先允许轻衡写入体重。"
            return
        }
        guard !records.isEmpty else {
            lastMessage = "目前没有需要同步的体重记录。"
            return
        }

        isSyncing = true
        lastMessage = nil
        defer { isSyncing = false }

        do {
            try await healthStore.save(records.map(makeSample(from:)))
            lastMessage = "已同步 \(records.count) 条体重记录到 Apple 健康。"
        } catch {
            lastMessage = "历史记录同步失败：\(error.localizedDescription)"
        }
    }

    func deleteWeight(id: UUID) async {
        refreshAuthorizationStatus()
        guard state == .authorized else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [syncIdentifier(for: id)]
        )

        do {
            _ = try await healthStore.deleteObjects(of: bodyMassType, predicate: predicate)
        } catch {
            lastMessage = "Apple 健康中的对应记录未删除：\(error.localizedDescription)"
        }
    }

    private func makeSample(from record: WeightRecord) -> HKQuantitySample {
        let quantity = HKQuantity(
            unit: .gramUnit(with: .kilo),
            doubleValue: record.weightKg
        )
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier(for: record.id),
            HKMetadataKeySyncVersion: max(1, record.healthSyncVersion),
            HKMetadataKeyWasUserEntered: record.source == .manual
        ]
        let device: HKDevice? = if record.source == .bluetooth {
            HKDevice(
                name: record.deviceName ?? "小米体重秤",
                manufacturer: "Xiaomi",
                model: nil,
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: nil,
                localIdentifier: nil,
                udiDeviceIdentifier: nil
            )
        } else {
            nil
        }

        return HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: record.measuredAt,
            end: record.measuredAt,
            device: device,
            metadata: metadata
        )
    }

    private func syncIdentifier(for id: UUID) -> String {
        "\(Bundle.main.bundleIdentifier ?? "org.qingheng.app").weight.\(id.uuidString.lowercased())"
    }

    private var wellnessReadTypes: Set<HKObjectType> {
        [stepType, activeEnergyType, exerciseTimeType, sleepType]
    }

    private func cumulativeSum(
        type: HKQuantityType,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
                }
            }
            healthStore.execute(query)
        }
    }

    private func asleepMinutes(start: Date, end: Date) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: []
            )
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let intervals = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .compactMap { sample -> DateInterval? in
                        let clippedStart = max(sample.startDate, start)
                        let clippedEnd = min(sample.endDate, end)
                        return clippedEnd > clippedStart
                            ? DateInterval(start: clippedStart, end: clippedEnd)
                            : nil
                    }
                continuation.resume(returning: Self.mergedMinutes(intervals))
            }
            healthStore.execute(query)
        }
    }

    private func roundedPositive(_ value: Double?) -> Int? {
        guard let value, value > 0 else { return nil }
        return Int(value.rounded())
    }

    nonisolated static func mergedMinutes(_ intervals: [DateInterval]) -> Int {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var seconds: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                seconds += current.duration
                current = interval
            }
        }
        seconds += current.duration
        return Int((seconds / 60).rounded())
    }
}

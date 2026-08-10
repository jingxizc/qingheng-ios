import Combine
import Foundation
import HealthKit

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
                return "轻衡只写入体重，不会读取你的其他健康数据。"
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

    private let healthStore = HKHealthStore()
    private let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!

    init() {
        refreshAuthorizationStatus()
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
}

import Foundation
import SwiftData

enum WeightSource: String, Codable, CaseIterable {
    case bluetooth
    case manual

    var title: String {
        switch self {
        case .bluetooth: "小米体重秤"
        case .manual: "手动记录"
        }
    }

    var symbol: String {
        switch self {
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .manual: "hand.tap"
        }
    }
}

@Model
final class WeightRecord {
    @Attribute(.unique) var id: UUID
    var weightKg: Double
    var measuredAt: Date
    var sourceRawValue: String
    var deviceName: String?
    var sessionStartedAt: Date?
    var sessionUpdatedAt: Date?
    var sessionReadingsText: String = ""
    var mergedReadingCount: Int = 1
    var rejectedReadingCount: Int = 0
    var readingSpreadKg: Double?
    var healthSyncVersion: Int = 1

    init(
        id: UUID = UUID(),
        weightKg: Double,
        measuredAt: Date = .now,
        source: WeightSource = .manual,
        deviceName: String? = nil
    ) {
        self.id = id
        self.weightKg = weightKg
        self.measuredAt = measuredAt
        self.sourceRawValue = source.rawValue
        self.deviceName = deviceName

        if source == .bluetooth {
            self.sessionStartedAt = measuredAt
            self.sessionUpdatedAt = measuredAt
            self.sessionReadingsText = String(weightKg)
        }
    }

    var source: WeightSource {
        WeightSource(rawValue: sourceRawValue) ?? .manual
    }

    var sessionReadings: [Double] {
        let values = sessionReadingsText
            .split(separator: "|")
            .compactMap { Double($0) }
        return values.isEmpty ? [weightKg] : values
    }

    var wasMerged: Bool {
        source == .bluetooth && mergedReadingCount > 1
    }

    var sessionSummary: String? {
        guard wasMerged else { return nil }
        if let readingSpreadKg, readingSpreadKg >= 0.05 {
            return "\(mergedReadingCount) 次读数合并 · 波动 \(String(format: "%.2f", readingSpreadKg)) kg"
        }
        return "\(mergedReadingCount) 次稳定读数已合并"
    }

    @discardableResult
    func mergeBluetoothMeasurement(weightKg newWeight: Double, measuredAt newDate: Date) -> WeightSessionAggregate {
        let aggregate = WeightSessionPolicy.aggregate(sessionReadings + [newWeight])
        weightKg = aggregate.representativeWeight
        sessionUpdatedAt = newDate
        sessionReadingsText = aggregate.allReadings.map { String($0) }.joined(separator: "|")
        mergedReadingCount = aggregate.allReadings.count
        rejectedReadingCount = aggregate.rejectedCount
        readingSpreadKg = aggregate.spreadKg
        healthSyncVersion += 1
        return aggregate
    }
}

struct WeightSessionAggregate: Equatable {
    let representativeWeight: Double
    let allReadings: [Double]
    let acceptedReadings: [Double]
    let rejectedCount: Int
    let spreadKg: Double
}

enum WeightSessionPolicy {
    static let duration: TimeInterval = 5 * 60
    static let maximumJoinDistanceKg = 0.8

    static func canMerge(
        existingWeight: Double,
        lastUpdatedAt: Date,
        existingDeviceName: String?,
        newWeight: Double,
        newDate: Date,
        newDeviceName: String?
    ) -> Bool {
        let elapsed = newDate.timeIntervalSince(lastUpdatedAt)
        guard elapsed >= 0, elapsed <= duration,
              abs(existingWeight - newWeight) <= maximumJoinDistanceKg
        else {
            return false
        }

        if let existingDeviceName, let newDeviceName {
            return existingDeviceName == newDeviceName
        }
        return true
    }

    static func aggregate(_ readings: [Double]) -> WeightSessionAggregate {
        let valid = readings.filter { $0.isFinite && $0 >= 10 && $0 <= 350 }
        guard !valid.isEmpty else {
            return WeightSessionAggregate(
                representativeWeight: 0,
                allReadings: [],
                acceptedReadings: [],
                rejectedCount: 0,
                spreadKg: 0
            )
        }

        let center = median(valid)
        let deviations = valid.map { abs($0 - center) }
        let medianDeviation = median(deviations)
        let threshold = min(0.45, max(0.15, medianDeviation * 3))
        var accepted = valid.filter { abs($0 - center) <= threshold + 0.000_1 }
        let minimumAccepted = max(1, (valid.count + 1) / 2)

        if accepted.count < minimumAccepted {
            accepted = valid
                .sorted { abs($0 - center) < abs($1 - center) }
                .prefix(minimumAccepted)
                .map { $0 }
        }

        let representative = roundedToScaleResolution(median(accepted))
        let minimum = accepted.min() ?? representative
        let maximum = accepted.max() ?? representative

        return WeightSessionAggregate(
            representativeWeight: representative,
            allReadings: valid,
            acceptedReadings: accepted,
            rejectedCount: valid.count - accepted.count,
            spreadKg: maximum - minimum
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func roundedToScaleResolution(_ value: Double) -> Double {
        (value * 20).rounded() / 20
    }
}

struct PersonalWeightAssessment: Equatable {
    let isPlausible: Bool
    let referenceWeightKg: Double?
    let maximumDeviationKg: Double?
}

enum PersonalWeightPolicy {
    private static let referenceWindow: TimeInterval = 90 * 24 * 60 * 60

    static func assess(
        newWeightKg: Double,
        measuredAt: Date,
        against records: [WeightRecord]
    ) -> PersonalWeightAssessment {
        guard newWeightKg.isFinite, newWeightKg >= 10, newWeightKg <= 350 else {
            return PersonalWeightAssessment(
                isPlausible: false,
                referenceWeightKg: nil,
                maximumDeviationKg: nil
            )
        }

        let cutoff = measuredAt.addingTimeInterval(-referenceWindow)
        let recent = records
            .filter {
                $0.measuredAt >= cutoff
                    && $0.measuredAt <= measuredAt
                    && $0.weightKg.isFinite
                    && $0.weightKg >= 10
                    && $0.weightKg <= 350
            }
            .sorted { $0.measuredAt < $1.measuredAt }

        guard !recent.isEmpty else {
            return PersonalWeightAssessment(
                isPlausible: true,
                referenceWeightKg: nil,
                maximumDeviationKg: nil
            )
        }

        // A manual entry is an explicit confirmation and lets the user establish
        // a new baseline after a long gap or a genuinely large body-weight change.
        let reference: Double
        if let confirmed = recent.last, confirmed.source == .manual {
            reference = confirmed.weightKg
        } else if recent.count <= 2 {
            // With only two values, prefer the older established value so that a
            // single newly imported outlier cannot immediately become the baseline.
            reference = recent[0].weightKg
        } else {
            reference = median(recent.map(\.weightKg))
        }

        let maximumDeviation = min(8, max(4, reference * 0.07))
        return PersonalWeightAssessment(
            isPlausible: abs(newWeightKg - reference) <= maximumDeviation,
            referenceWeightKg: reference,
            maximumDeviationKg: maximumDeviation
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

enum WeightAnalytics {
    static func change(in records: [WeightRecord]) -> Double? {
        guard records.count > 1,
              let newest = records.max(by: { $0.measuredAt < $1.measuredAt }),
              let oldest = records.min(by: { $0.measuredAt < $1.measuredAt })
        else {
            return nil
        }
        return newest.weightKg - oldest.weightKg
    }

    static func average(in records: [WeightRecord]) -> Double? {
        guard !records.isEmpty else { return nil }
        return records.reduce(0) { $0 + $1.weightKg } / Double(records.count)
    }

    static func progress(start: Double, current: Double, target: Double) -> Double {
        let total = start - target
        guard abs(total) > 0.001 else { return 1 }
        return min(max((start - current) / total, 0), 1)
    }
}

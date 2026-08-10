import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sun.max.fill"
        case .lunch: "takeoutbag.and.cup.and.straw.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}

@Model
final class MealRecord {
    @Attribute(.unique) var id: UUID
    var eatenAt: Date
    var mealTypeRawValue: String
    var note: String
    @Attribute(.externalStorage) var photoData: Data?
    var portionRawValue: String = MealPortion.regular.rawValue
    var analysisTagsText: String = ""
    var analysisGroupsText: String = ""
    var visionLabelsText: String = ""
    var analysisSummary: String = ""
    var estimatedCaloriesLow: Int?
    var estimatedCaloriesHigh: Int?
    var nutritionScore: Int?
    var analysisConfidence: Double?
    var analyzedAt: Date?
    var analysisVersion: Int = 0
    var isUserCorrected: Bool = false
    var correctedAt: Date?
    var correctionCount: Int = 0

    init(
        id: UUID = UUID(),
        eatenAt: Date = .now,
        mealType: MealType,
        note: String = "",
        photoData: Data? = nil,
        portion: MealPortion = .regular,
        analysis: FoodVisionAnalysis? = nil
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.mealTypeRawValue = mealType.rawValue
        self.note = note
        self.photoData = photoData
        self.portionRawValue = portion.rawValue

        if let analysis {
            apply(analysis, portion: portion)
        }
    }

    var mealType: MealType {
        MealType(rawValue: mealTypeRawValue) ?? .snack
    }

    var portion: MealPortion {
        MealPortion(rawValue: portionRawValue) ?? .regular
    }

    var analysisTags: [String] {
        split(analysisTagsText)
    }

    var analysisGroups: [FoodGroup] {
        split(analysisGroupsText).compactMap(FoodGroup.init(rawValue:))
    }

    var visionLabels: [String] {
        split(visionLabelsText)
    }

    var hasAnalysis: Bool {
        analyzedAt != nil && analysisVersion > 0
    }

    var calorieRangeText: String? {
        guard let estimatedCaloriesLow, let estimatedCaloriesHigh else { return nil }
        return "\(estimatedCaloriesLow)–\(estimatedCaloriesHigh) 千卡"
    }

    func apply(_ analysis: FoodVisionAnalysis, portion: MealPortion) {
        portionRawValue = portion.rawValue
        analysisTagsText = analysis.tags.joined(separator: "|")
        analysisGroupsText = analysis.groups.map(\.rawValue).joined(separator: "|")
        visionLabelsText = analysis.rawLabels.joined(separator: "|")
        analysisSummary = analysis.summary
        analysisConfidence = analysis.confidence
        nutritionScore = analysis.nutritionScore

        if let range = analysis.calorieRange(for: portion) {
            estimatedCaloriesLow = range.lowerBound
            estimatedCaloriesHigh = range.upperBound
        } else {
            estimatedCaloriesLow = nil
            estimatedCaloriesHigh = nil
        }

        analyzedAt = .now
        analysisVersion = max(1, analysisVersion + 1)
        let usedLearnedCorrection = FoodCorrectionMemory.correction(for: analysis.rawLabels) != nil
        isUserCorrected = usedLearnedCorrection
        correctedAt = usedLearnedCorrection ? .now : nil
    }

    func applyCorrection(
        tags: [String],
        groups: [FoodGroup],
        portion: MealPortion,
        caloriesLow: Int,
        caloriesHigh: Int
    ) {
        var seenTags = Set<String>()
        let cleanedTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenTags.insert($0).inserted }
        var seenGroups = Set<FoodGroup>()
        let cleanedGroups = groups.filter { seenGroups.insert($0).inserted }
        let low = min(max(0, caloriesLow), 4_000)
        let high = min(max(low, caloriesHigh), 4_000)

        portionRawValue = portion.rawValue
        analysisTagsText = cleanedTags.joined(separator: "|")
        analysisGroupsText = cleanedGroups.map(\.rawValue).joined(separator: "|")
        estimatedCaloriesLow = low
        estimatedCaloriesHigh = high
        nutritionScore = FoodKnowledgeBase.nutritionScore(for: cleanedGroups, tags: cleanedTags)
        analysisSummary = FoodKnowledgeBase.confirmedSummary(tags: cleanedTags, groups: cleanedGroups)
        analyzedAt = analyzedAt ?? .now
        analysisVersion = max(2, analysisVersion + 1)
        isUserCorrected = true
        correctedAt = .now
        correctionCount += 1

        FoodCorrectionMemory.remember(
            labels: visionLabels,
            tags: cleanedTags,
            groups: cleanedGroups,
            portion: portion,
            caloriesLow: low,
            caloriesHigh: high
        )
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }
}

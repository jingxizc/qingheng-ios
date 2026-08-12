import Foundation
import Vision

enum MealPortion: String, CaseIterable, Identifiable, Codable {
    case small
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "少量"
        case .regular: "适中"
        case .large: "较多"
        }
    }

    var factor: Double {
        switch self {
        case .small: 0.72
        case .regular: 1
        case .large: 1.32
        }
    }
}

enum FoodGroup: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case carbohydrate
    case protein
    case vegetable
    case fruit
    case dairy
    case soup
    case dessert
    case fried
    case fastFood
    case drink
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carbohydrate: "主食"
        case .protein: "蛋白质"
        case .vegetable: "蔬菜"
        case .fruit: "水果"
        case .dairy: "奶制品"
        case .soup: "汤羹"
        case .dessert: "甜点"
        case .fried: "油炸"
        case .fastFood: "高能量餐食"
        case .drink: "饮品"
        case .mixed: "混合餐食"
        }
    }
}

struct FoodVisionObservation: Equatable, Sendable {
    let identifier: String
    let confidence: Float
}

struct FoodVisionAnalysis: Equatable, Sendable {
    let tags: [String]
    let groups: [FoodGroup]
    let mediumCaloriesLow: Int?
    let mediumCaloriesHigh: Int?
    let nutritionScore: Int?
    let summary: String
    let confidence: Double
    let rawLabels: [String]

    var isRecognized: Bool {
        !tags.isEmpty && mediumCaloriesLow != nil && mediumCaloriesHigh != nil
    }

    func calorieRange(for portion: MealPortion) -> ClosedRange<Int>? {
        guard let mediumCaloriesLow, let mediumCaloriesHigh else { return nil }
        let low = Int((Double(mediumCaloriesLow) * portion.factor / 10).rounded() * 10)
        let high = Int((Double(mediumCaloriesHigh) * portion.factor / 10).rounded() * 10)
        return low...max(low, high)
    }
}

struct MealRefinementResult: Equatable, Sendable {
    let caloriesLow: Int
    let caloriesHigh: Int
    let nutritionScore: Int
    let summary: String
    let confidence: Double
}

enum FoodVisionAnalyzer {
    enum AnalysisError: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            "这张照片暂时无法分析，请重新拍摄或换一张照片。"
        }
    }

    static func analyze(imageData: Data) async throws -> FoodVisionAnalysis {
        guard !imageData.isEmpty else { throw AnalysisError.unreadableImage }

        let observations = try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            return (request.results ?? [])
                .filter { $0.confidence >= 0.025 }
                .prefix(18)
                .map {
                    FoodVisionObservation(
                        identifier: $0.identifier,
                        confidence: $0.confidence
                    )
                }
        }.value

        let baseAnalysis = FoodKnowledgeBase.analyze(observations: observations)
        guard let correction = FoodCorrectionMemory.correction(
            for: observations.map(\.identifier)
        ) else {
            return baseAnalysis
        }

        let groups = correction.groupRawValues.compactMap(FoodGroup.init(rawValue:))
        guard !correction.tags.isEmpty, !groups.isEmpty else { return baseAnalysis }

        return FoodVisionAnalysis(
            tags: correction.tags,
            groups: groups,
            mediumCaloriesLow: correction.regularCaloriesLow,
            mediumCaloriesHigh: correction.regularCaloriesHigh,
            nutritionScore: FoodKnowledgeBase.nutritionScore(for: groups, tags: correction.tags),
            summary: FoodKnowledgeBase.confirmedSummary(tags: correction.tags, groups: groups),
            confidence: max(baseAnalysis.confidence, 0.92),
            rawLabels: baseAnalysis.rawLabels
        )
    }
}

struct FoodCorrection: Codable, Equatable {
    let tags: [String]
    let groupRawValues: [String]
    let regularCaloriesLow: Int
    let regularCaloriesHigh: Int
}

enum FoodCorrectionMemory {
    private static let storageKey = "foodVisionCorrectionsV1"

    static func correction(for labels: [String]) -> FoodCorrection? {
        guard let signature = signature(for: labels) else { return nil }
        return storedCorrections()[signature]
    }

    static func remember(
        labels: [String],
        tags: [String],
        groups: [FoodGroup],
        portion: MealPortion,
        caloriesLow: Int,
        caloriesHigh: Int
    ) {
        guard let signature = signature(for: labels),
              !tags.isEmpty,
              !groups.isEmpty
        else {
            return
        }

        let factor = max(portion.factor, 0.01)
        let regularLow = max(0, Int((Double(caloriesLow) / factor / 10).rounded() * 10))
        let regularHigh = max(
            regularLow,
            Int((Double(caloriesHigh) / factor / 10).rounded() * 10)
        )
        var values = storedCorrections()
        values[signature] = FoodCorrection(
            tags: tags,
            groupRawValues: groups.map(\.rawValue),
            regularCaloriesLow: regularLow,
            regularCaloriesHigh: regularHigh
        )

        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func storedCorrections() -> [String: FoodCorrection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: FoodCorrection].self, from: data)
        else {
            return [:]
        }
        return values
    }

    private static func signature(for labels: [String]) -> String? {
        let normalized = labels
            .map {
                $0.lowercased()
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }

        let genericLabels: Set<String> = [
            "food", "dish", "meal", "cuisine", "plate", "tableware", "ingredient"
        ]
        let meaningful = normalized.filter { !genericLabels.contains($0) }
        let source = meaningful.isEmpty ? normalized : meaningful
        return source.prefix(2).joined(separator: "¦")
    }
}

enum FoodKnowledgeBase {
    private struct Rule {
        let keywords: [String]
        let tag: String
        let group: FoodGroup
    }

    private struct Match {
        let tag: String
        let group: FoodGroup
        let confidence: Float
    }

    // Vision currently returns English identifiers. Keep specific composite foods
    // before their individual ingredients so one image does not get double-counted.
    private static let rules: [Rule] = [
        Rule(keywords: ["fried chicken"], tag: "炸鸡", group: .fried),
        Rule(keywords: ["french fries", "french fry"], tag: "薯条", group: .fried),
        Rule(keywords: ["pizza"], tag: "披萨", group: .fastFood),
        Rule(keywords: ["cheeseburger", "hamburger", "burger"], tag: "汉堡", group: .fastFood),
        Rule(keywords: ["hot dog"], tag: "热狗", group: .fastFood),
        Rule(keywords: ["sandwich", "submarine sandwich"], tag: "三明治", group: .mixed),
        Rule(keywords: ["burrito", "taco", "quesadilla"], tag: "卷饼", group: .mixed),
        Rule(keywords: ["sushi", "sashimi"], tag: "寿司", group: .mixed),
        Rule(keywords: ["curry"], tag: "咖喱", group: .mixed),
        Rule(keywords: ["hotpot", "hot pot"], tag: "火锅", group: .mixed),
        Rule(keywords: ["spaghetti", "pasta", "macaroni", "noodle", "ramen", "chow mein"], tag: "面食", group: .carbohydrate),
        Rule(keywords: ["fried rice", "rice", "congee", "porridge"], tag: "米饭", group: .carbohydrate),
        Rule(keywords: ["dumpling", "wonton", "gyoza", "ravioli"], tag: "饺子", group: .carbohydrate),
        Rule(keywords: ["bread", "toast", "bagel", "bun", "croissant"], tag: "面包", group: .carbohydrate),
        Rule(keywords: ["potato", "sweet potato"], tag: "薯类", group: .carbohydrate),
        Rule(keywords: ["corn"], tag: "玉米", group: .carbohydrate),
        Rule(keywords: ["salmon", "tuna", "fish", "seafood"], tag: "鱼类", group: .protein),
        Rule(keywords: ["shrimp", "prawn", "crab", "lobster"], tag: "海鲜", group: .protein),
        Rule(keywords: ["chicken", "turkey", "duck"], tag: "禽肉", group: .protein),
        Rule(keywords: ["beef", "steak", "veal"], tag: "牛肉", group: .protein),
        Rule(keywords: ["pork", "bacon", "ham", "sausage"], tag: "猪肉", group: .protein),
        Rule(keywords: ["egg", "omelet", "omelette"], tag: "鸡蛋", group: .protein),
        Rule(keywords: ["tofu", "bean curd", "soybean", "beans"], tag: "豆制品", group: .protein),
        Rule(keywords: ["salad", "lettuce", "broccoli", "spinach", "cabbage", "cauliflower", "vegetable", "greens"], tag: "蔬菜", group: .vegetable),
        Rule(keywords: ["tomato", "cucumber", "pepper", "carrot", "mushroom", "asparagus"], tag: "蔬菜", group: .vegetable),
        Rule(keywords: ["apple", "banana", "orange", "berry", "berries", "grape", "watermelon", "melon", "pineapple", "mango", "fruit"], tag: "水果", group: .fruit),
        Rule(keywords: ["milk", "yogurt", "yoghurt", "cheese"], tag: "奶制品", group: .dairy),
        Rule(keywords: ["soup", "stew", "broth"], tag: "汤羹", group: .soup),
        Rule(keywords: ["cake", "cupcake", "donut", "doughnut", "cookie", "brownie", "pastry", "dessert"], tag: "甜点", group: .dessert),
        Rule(keywords: ["ice cream", "gelato"], tag: "冰淇淋", group: .dessert),
        Rule(keywords: ["pancake", "waffle"], tag: "甜味主食", group: .dessert),
        Rule(keywords: ["soda", "soft drink", "cola", "bubble tea", "milk tea", "juice"], tag: "含糖饮品", group: .drink),
        Rule(keywords: ["coffee", "tea", "beverage", "drink"], tag: "饮品", group: .drink),
        Rule(keywords: ["food", "dish", "meal", "cuisine", "plate"], tag: "餐食", group: .mixed)
    ]

    static func analyze(observations: [FoodVisionObservation]) -> FoodVisionAnalysis {
        let rawLabels = observations.prefix(8).map(\.identifier)
        var matches: [Match] = []
        var seenTags = Set<String>()

        for observation in observations.sorted(by: { $0.confidence > $1.confidence }) {
            let identifier = normalized(observation.identifier)
            guard let rule = rules.first(where: { rule in
                rule.keywords.contains(where: { identifier.contains($0) })
            }) else {
                continue
            }

            let isGeneric = rule.tag == "餐食"
            let minimumConfidence: Float = isGeneric ? 0.12 : 0.045
            guard observation.confidence >= minimumConfidence,
                  seenTags.insert(rule.tag).inserted
            else {
                continue
            }

            matches.append(
                Match(tag: rule.tag, group: rule.group, confidence: observation.confidence)
            )
            if matches.count == 5 { break }
        }

        guard !matches.isEmpty else {
            return FoodVisionAnalysis(
                tags: [],
                groups: [],
                mediumCaloriesLow: nil,
                mediumCaloriesHigh: nil,
                nutritionScore: nil,
                summary: "暂未可靠识别出食物，可以换个角度拍摄，或在备注里写下主要食材。",
                confidence: Double(observations.first?.confidence ?? 0),
                rawLabels: rawLabels
            )
        }

        let tags = matches.map(\.tag)
        let groups = uniqueGroups(from: matches)
        let calorieRange = estimatedCalories(for: groups, tags: tags)
        let score = nutritionScore(for: groups, tags: tags)

        return FoodVisionAnalysis(
            tags: tags,
            groups: groups,
            mediumCaloriesLow: calorieRange.lowerBound,
            mediumCaloriesHigh: calorieRange.upperBound,
            nutritionScore: score,
            summary: summary(tags: tags, groups: groups),
            confidence: Double(matches.map(\.confidence).max() ?? 0),
            rawLabels: rawLabels
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func uniqueGroups(from matches: [Match]) -> [FoodGroup] {
        var seen = Set<FoodGroup>()
        return matches.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    private static func estimatedCalories(
        for groups: [FoodGroup],
        tags: [String]
    ) -> ClosedRange<Int> {
        let set = Set(groups)

        if set.contains(.fastFood) { return 600...1_000 }
        if set.contains(.fried) { return 480...880 }
        if tags.contains("火锅") { return 650...1_100 }
        if tags.contains("披萨") || tags.contains("汉堡") { return 600...1_000 }
        if set.contains(.mixed), set.count == 1 { return 380...760 }
        if set.contains(.dessert), set.count == 1 { return 240...540 }

        var low = 0
        var high = 0

        if set.contains(.carbohydrate) {
            low += 180
            high += 360
        }
        if set.contains(.protein) {
            low += 160
            high += 380
        }
        if set.contains(.vegetable) {
            low += 60
            high += 180
        }
        if set.contains(.fruit) {
            low += 60
            high += 180
        }
        if set.contains(.dairy) {
            low += 90
            high += 260
        }
        if set.contains(.soup) {
            low += 120
            high += 380
        }
        if set.contains(.dessert) {
            low += 180
            high += 420
        }
        if set.contains(.drink) {
            low += tags.contains("含糖饮品") ? 120 : 0
            high += tags.contains("含糖饮品") ? 320 : 80
        }
        if set.contains(.mixed) {
            low = max(low, 380)
            high = max(high, 760)
        }

        return max(40, low)...max(max(160, high), low)
    }

    static func nutritionScore(for groups: [FoodGroup], tags: [String]) -> Int {
        let set = Set(groups)
        var score = 55

        if set.contains(.vegetable) { score += 15 }
        if set.contains(.protein) { score += 10 }
        if set.contains(.fruit) { score += 7 }
        if set.contains(.dairy) { score += 4 }
        if set.isSuperset(of: [.carbohydrate, .protein, .vegetable]) { score += 8 }
        if set.contains(.fried) { score -= 20 }
        if set.contains(.fastFood) { score -= 18 }
        if set.contains(.dessert) { score -= 13 }
        if tags.contains("含糖饮品") { score -= 10 }

        return min(max(score, 30), 95)
    }

    private static func summary(tags: [String], groups: [FoodGroup]) -> String {
        let joinedTags = tags.prefix(4).joined(separator: "、")
        let set = Set(groups)

        if set.isSuperset(of: [.carbohydrate, .protein, .vegetable]) {
            return "识别到\(joinedTags)，主食、蛋白质和蔬菜比较齐全。"
        }
        if set.contains(.fried) || set.contains(.fastFood) {
            return "识别到\(joinedTags)，这餐能量可能偏高，下一餐可以用蔬菜和清淡蛋白质平衡。"
        }
        if set.contains(.dessert) {
            return "识别到\(joinedTags)，把它当作一次正常记录即可，留意份量和含糖饮品。"
        }
        if !set.contains(.vegetable), set.contains(.carbohydrate) || set.contains(.protein) {
            return "识别到\(joinedTags)，如果盘中还有蔬菜，换个角度拍摄会更容易识别。"
        }
        return "识别到\(joinedTags)，结果已用于今天的饮食趋势。"
    }

    static func confirmedSummary(tags: [String], groups: [FoodGroup]) -> String {
        let base = summary(tags: tags, groups: groups)
        return "已按你的确认更新。\(base)"
    }
}

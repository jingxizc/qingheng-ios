import Combine
import Foundation
import LocalAuthentication
import Security
import UIKit

struct QwenConfiguration: Codable, Equatable, Sendable {
    let version: Int
    let provider: String
    let region: String
    let workspaceID: String?
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case provider
        case region
        case workspaceID = "workspace_id"
        case apiKey = "api_key"
    }

    enum ConfigurationError: LocalizedError {
        case invalidPayload
        case unsupportedVersion
        case unsupportedProvider
        case unsupportedRegion
        case invalidWorkspace
        case invalidAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidPayload: "这不是有效的轻衡 AI 配置二维码。"
            case .unsupportedVersion: "二维码版本暂不支持，请重新生成。"
            case .unsupportedProvider: "二维码中的 AI 服务商不受支持。"
            case .unsupportedRegion: "目前仅支持千问北京或新加坡地域。"
            case .invalidWorkspace: "Workspace ID 格式不正确。"
            case .invalidAPIKey: "API Key 格式不正确。"
            }
        }
    }

    static func decodeQRCodePayload(_ rawValue: String) throws -> QwenConfiguration {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(QwenConfiguration.self, from: data)
        else {
            throw ConfigurationError.invalidPayload
        }
        try value.validate()
        return value
    }

    func validate() throws {
        guard [1, 2].contains(version) else { throw ConfigurationError.unsupportedVersion }
        guard provider.lowercased() == "dashscope" else {
            throw ConfigurationError.unsupportedProvider
        }
        guard ["cn-beijing", "ap-southeast-1"].contains(region) else {
            throw ConfigurationError.unsupportedRegion
        }

        let normalizedWorkspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if version == 1, normalizedWorkspaceID?.isEmpty != false {
            throw ConfigurationError.invalidWorkspace
        }
        if let normalizedWorkspaceID, !normalizedWorkspaceID.isEmpty {
            let allowedWorkspaceCharacters = CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-_")
            )
            guard normalizedWorkspaceID.unicodeScalars.allSatisfy(allowedWorkspaceCharacters.contains),
                  normalizedWorkspaceID.count <= 128
            else {
                throw ConfigurationError.invalidWorkspace
            }
        }

        guard apiKey.hasPrefix("sk-"), apiKey.count >= 12, apiKey.count <= 512 else {
            throw ConfigurationError.invalidAPIKey
        }
    }

    var endpointURL: URL? {
        let normalizedWorkspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        if let normalizedWorkspaceID, !normalizedWorkspaceID.isEmpty {
            switch region {
            case "cn-beijing":
                host = "\(normalizedWorkspaceID).cn-beijing.maas.aliyuncs.com"
            case "ap-southeast-1":
                host = "\(normalizedWorkspaceID).ap-southeast-1.maas.aliyuncs.com"
            default:
                return nil
            }
        } else {
            switch region {
            case "cn-beijing":
                host = "dashscope.aliyuncs.com"
            case "ap-southeast-1":
                host = "dashscope-intl.aliyuncs.com"
            default:
                return nil
            }
        }
        return URL(string: "https://\(host)/compatible-mode/v1/chat/completions")
    }

    var regionTitle: String {
        switch region {
        case "cn-beijing": "北京"
        case "ap-southeast-1": "新加坡"
        default: region
        }
    }

    var connectionScope: String {
        guard let workspaceID, !workspaceID.isEmpty else { return "按量付费公共接口" }
        guard workspaceID.count > 6 else { return "业务空间 \(workspaceID)" }
        return "业务空间 ••••\(workspaceID.suffix(6))"
    }
}

private enum QwenCredentialStore {
    private static let service = "\(Bundle.main.bundleIdentifier ?? "org.qingheng.app").qwen.v1"
    private static let account = "dashscope"

    enum StoreError: LocalizedError {
        case encodingFailed
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "无法准备安全配置。"
            case let .keychain(status): "系统钥匙串暂时不可用（\(status)）。"
            }
        }
    }

    static func load() throws -> QwenConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = item as? Data,
              let configuration = try? JSONDecoder().decode(QwenConfiguration.self, from: data)
        else {
            throw StoreError.encodingFailed
        }
        try configuration.validate()
        return configuration
    }

    static func save(_ configuration: QwenConfiguration) throws {
        guard let data = try? JSONEncoder().encode(configuration) else {
            throw StoreError.encodingFailed
        }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    static func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}

struct QwenMealPayload: Decodable, Equatable {
    struct Food: Decodable, Equatable {
        let name: String
        let group: String
        let caloriesLow: Int?
        let caloriesHigh: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case group
            case caloriesLow = "calories_low"
            case caloriesHigh = "calories_high"
        }
    }

    let foods: [Food]
    let totalCaloriesLow: Int
    let totalCaloriesHigh: Int
    let nutritionScore: Int?
    let summary: String
    let confidence: Double
    let uncertainties: [String]

    enum CodingKeys: String, CodingKey {
        case foods
        case totalCaloriesLow = "total_calories_low"
        case totalCaloriesHigh = "total_calories_high"
        case nutritionScore = "nutrition_score"
        case summary
        case confidence
        case uncertainties
    }

    enum PayloadError: LocalizedError {
        case invalidAnalysis

        var errorDescription: String? {
            "云端模型返回的信息不完整，已改用本机分析。"
        }
    }

    func makeAnalysis(portion: MealPortion) throws -> FoodVisionAnalysis {
        let cleanFoods = foods.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groups = unique(cleanFoods.compactMap { Self.foodGroup(from: $0.group) })
        let tags = unique(cleanFoods.map { String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18)) })
        let low = min(max(totalCaloriesLow, 30), 4_000)
        let high = min(max(totalCaloriesHigh, low), 4_000)
        guard !tags.isEmpty, !groups.isEmpty, high >= low else {
            throw PayloadError.invalidAnalysis
        }

        let portionFactor = max(0.01, portion.factor)
        let regularLow = Int((Double(low) / portionFactor / 10).rounded() * 10)
        let regularHigh = max(
            regularLow,
            Int((Double(high) / portionFactor / 10).rounded() * 10)
        )
        let normalizedConfidence = confidence > 1 ? confidence / 100 : confidence
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let uncertaintyText = uncertainties
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "、")
        let combinedSummary: String
        if uncertaintyText.isEmpty {
            combinedSummary = cleanSummary
        } else {
            combinedSummary = "\(cleanSummary) 主要不确定项：\(uncertaintyText)。"
        }

        return FoodVisionAnalysis(
            tags: tags,
            groups: groups,
            mediumCaloriesLow: max(20, regularLow),
            mediumCaloriesHigh: min(4_000, max(regularLow, regularHigh)),
            nutritionScore: min(max(nutritionScore ?? FoodKnowledgeBase.nutritionScore(for: groups, tags: tags), 0), 100),
            summary: String(combinedSummary.prefix(180)),
            confidence: min(max(normalizedConfidence, 0), 1),
            rawLabels: tags
        )
    }

    private static func foodGroup(from rawValue: String) -> FoodGroup? {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        return switch normalized {
        case "carbohydrate", "carb", "主食": .carbohydrate
        case "protein", "蛋白质": .protein
        case "vegetable", "vegetables", "蔬菜": .vegetable
        case "fruit", "水果": .fruit
        case "dairy", "奶制品": .dairy
        case "soup", "汤羹": .soup
        case "dessert", "甜点": .dessert
        case "fried", "油炸": .fried
        case "fastfood", "高能量餐食": .fastFood
        case "drink", "beverage", "饮品": .drink
        case "mixed", "混合餐食": .mixed
        default: nil
        }
    }

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

@MainActor
final class QwenAIService: ObservableObject {
    static let modelID = "qwen3.7-flash-2026-07-15"

    enum State: Equatable {
        case disconnected
        case ready(region: String, scope: String)
        case testing
        case failed(String)

        var title: String {
            switch self {
            case .disconnected: "尚未连接 Qwen"
            case .ready: "Qwen3.7 Flash 已连接"
            case .testing: "正在验证云端 AI"
            case .failed: "云端 AI 连接异常"
            }
        }

        var detail: String {
            switch self {
            case .disconnected:
                "扫描本地生成的配置二维码即可启用，不需要在 App 中输入密钥。"
            case let .ready(region, scope):
                "千问\(region) · \(scope) · 密钥仅保存在本机钥匙串。"
            case .testing:
                "正在向千问发送最小测试请求，不会上传体重或照片。"
            case let .failed(message):
                message
            }
        }

        var symbol: String {
            switch self {
            case .disconnected: "qrcode.viewfinder"
            case .ready: "checkmark.seal.fill"
            case .testing: "sparkles"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var isBusy: Bool { self == .testing }
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidEndpoint
        case invalidImage
        case invalidRequest
        case invalidResponse
        case api(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "尚未连接 Qwen。"
            case .invalidEndpoint: "千问服务地址无效，请重新生成配置。"
            case .invalidImage: "照片无法压缩，请换一张照片再试。"
            case .invalidRequest: "无法准备云端分析请求。"
            case .invalidResponse: "云端返回格式异常，已保留本机降级能力。"
            case let .api(message): message
            }
        }
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastFallbackReason: String?

    private var configuration: QwenConfiguration?

    var isConfigured: Bool { configuration != nil }
    var isCloudReady: Bool { state.isReady }

    init() {
        do {
            configuration = try QwenCredentialStore.load()
            updateReadyState()
        } catch {
            configuration = nil
            state = .failed(error.localizedDescription)
        }
    }

    func refreshConnectionIfConfigured() async {
        guard configuration != nil else { return }
        await testConnection()
    }

    func connect(qrPayload: String) async throws {
        let candidate = try QwenConfiguration.decodeQRCodePayload(qrPayload)
        state = .testing
        do {
            try await verify(candidate)
            try QwenCredentialStore.save(candidate)
            configuration = candidate
            lastFallbackReason = nil
            updateReadyState()
        } catch {
            state = .failed(safeMessage(for: error))
            throw error
        }
    }

    func testConnection() async {
        guard let configuration else {
            state = .disconnected
            return
        }
        state = .testing
        do {
            try await verify(configuration)
            updateReadyState()
        } catch {
            state = .failed(safeMessage(for: error))
        }
    }

    func removeConfiguration() throws {
        try QwenCredentialStore.remove()
        configuration = nil
        lastFallbackReason = nil
        state = .disconnected
    }

    func authorizeManagement() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "管理轻衡的云端 AI 连接"
            )
        } catch {
            return false
        }
    }

    func analyzeMealWithFallback(
        imageData: Data,
        portion: MealPortion
    ) async throws -> FoodVisionAnalysis {
        guard let configuration else {
            return try await FoodVisionAnalyzer.analyze(imageData: imageData)
        }

        do {
            let result = try await analyzeMeal(
                imageData: imageData,
                portion: portion,
                configuration: configuration
            )
            lastFallbackReason = nil
            return result
        } catch {
            lastFallbackReason = "Qwen 暂时不可用，本次已改用 Apple Vision。"
            return try await FoodVisionAnalyzer.analyze(imageData: imageData)
        }
    }

    func coachBrief(
        for context: CoachContext,
        fallback: CoachBrief
    ) async -> CoachBrief? {
        guard let configuration else { return nil }
        let system = """
        你是轻衡 App 的减重陪伴教练。只使用简体中文，只根据用户提供的数据判断。
        不诊断疾病，不鼓励极端节食，不羞辱用户。每次只给一个可执行的小行动。
        以严格 JSON 输出 headline、message、action。action 只能是 weigh、logMeal、reviewMeals、viewProgress、none。
        headline 不超过 18 个汉字，message 不超过 80 个汉字。
        """
        let user = """
        用户数据：
        \(context.promptDescription)

        本地安全规则建议：\(fallback.headline)；\(fallback.message)
        请综合数据生成今天最值得做的一步，并按照 JSON 输出。
        """

        do {
            let output = try await requestText(
                configuration: configuration,
                system: system,
                userContent: [["type": "text", "text": user]],
                jsonMode: true,
                enableThinking: false
            )
            let payload = try decodeJSON(QwenCoachPayload.self, from: output)
            return payload.makeBrief(fallback: fallback)
        } catch {
            lastFallbackReason = "Qwen 教练暂时不可用，本次已使用本机建议。"
            return nil
        }
    }

    func enhanceWeeklyReport(_ report: WeeklyCoachReport) async -> WeeklyCoachReport? {
        guard let configuration else { return nil }
        let system = """
        你是轻衡 App 的周复盘教练。只使用给定数据，不新增事实，不做医学诊断。
        语气温和、具体，不用羞辱或极端节食表达。只输出 JSON：headline、summary、win、focus、next_goal。
        next_goal 必须只有一个、能在 7 天内执行和计数的目标。
        """
        let user = """
        周期：\(report.periodText)
        当前体重：\(report.currentWeight.map { String(format: "%.1f kg", $0) } ?? "无")
        体重变化：\(report.weightChangeText)
        称重覆盖：\(report.weightCoverageText)
        饮食覆盖：\(report.mealCoverageText)，共 \(report.mealCount) 餐，已分析 \(report.analyzedMealCount) 餐
        本地复盘：\(report.summary)；优势：\(report.win)；重点：\(report.focus)；目标：\(report.nextGoal)
        请进行全面但简短的周复盘，并按照 JSON 输出。
        """

        do {
            let output = try await requestText(
                configuration: configuration,
                system: system,
                userContent: [["type": "text", "text": user]],
                jsonMode: true,
                enableThinking: true
            )
            let payload = try decodeJSON(QwenWeeklyPayload.self, from: output)
            return report.replacingNarrative(
                headline: payload.headline,
                summary: payload.summary,
                win: payload.win,
                focus: payload.focus,
                nextGoal: payload.nextGoal
            )
        } catch {
            lastFallbackReason = "Qwen 周报暂时不可用，本次已使用本机复盘。"
            return nil
        }
    }

    private func verify(_ configuration: QwenConfiguration) async throws {
        let output = try await requestText(
            configuration: configuration,
            system: "你是连接检测助手。",
            userContent: [["type": "text", "text": "只回复：连接成功"]],
            jsonMode: false,
            enableThinking: false
        )
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidResponse
        }
    }

    private func analyzeMeal(
        imageData: Data,
        portion: MealPortion,
        configuration: QwenConfiguration
    ) async throws -> FoodVisionAnalysis {
        guard let preparedImage = preparedJPEG(from: imageData) else {
            throw ServiceError.invalidImage
        }
        let imageURL = "data:image/jpeg;base64,\(preparedImage.base64EncodedString())"
        let system = """
        你是轻衡 App 的饮食照片分析器。识别画面中实际可见的食物，并估算热量范围。
        不能确定时必须扩大区间并降低 confidence，不能伪造精确克数。
        group 只能使用 carbohydrate、protein、vegetable、fruit、dairy、soup、dessert、fried、fastFood、drink、mixed。
        只输出严格 JSON，字段为：foods（name、group、calories_low、calories_high）、
        total_calories_low、total_calories_high、nutrition_score、summary、confidence、uncertainties。
        confidence 使用 0 到 1。nutrition_score 使用 0 到 100。
        """
        let prompt = """
        用户认为这餐份量是“\(portion.title)”。请结合照片估算这一次实际食用份量的热量范围，
        识别主要食物和餐盘结构。summary 用一句简短中文说明餐盘特点，不超过 70 个汉字。
        uncertainties 列出最多 3 个影响热量估算的因素。请按照 JSON 输出。
        """
        let output = try await requestText(
            configuration: configuration,
            system: system,
            userContent: [
                ["type": "image_url", "image_url": ["url": imageURL]],
                ["type": "text", "text": prompt]
            ],
            jsonMode: true,
            enableThinking: false
        )
        let payload = try decodeJSON(QwenMealPayload.self, from: output)
        return try payload.makeAnalysis(portion: portion)
    }

    private func requestText(
        configuration: QwenConfiguration,
        system: String,
        userContent: [[String: Any]],
        jsonMode: Bool,
        enableThinking: Bool
    ) async throws -> String {
        guard let endpoint = configuration.endpointURL else {
            throw ServiceError.invalidEndpoint
        }
        var body: [String: Any] = [
            "model": Self.modelID,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent]
            ],
            "enable_thinking": enableThinking,
            "stream": false
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        guard JSONSerialization.isValidJSONObject(body),
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else {
            throw ServiceError.invalidRequest
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 75
        sessionConfiguration.timeoutIntervalForResource = 90
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfiguration)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(QwenErrorEnvelope.self, from: data)
            let serverMessage = envelope?.error?.message ?? envelope?.message
            let message = serverMessage.map { String($0.prefix(120)) }
                ?? "千问请求失败（HTTP \(httpResponse.statusCode)）。"
            throw ServiceError.api(message)
        }
        guard let responseValue = try? JSONDecoder().decode(QwenChatResponse.self, from: data),
              let content = responseValue.choices.first?.message.content,
              !content.isEmpty
        else {
            throw ServiceError.invalidResponse
        }
        return content
    }

    private func preparedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximumDimension: CGFloat = 1_280
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / max(longestSide, 1))
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") { clean.removeFirst(7) }
        if clean.hasPrefix("```") { clean.removeFirst(3) }
        if clean.hasSuffix("```") { clean.removeLast(3) }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = clean.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(type, from: data)
        else {
            throw ServiceError.invalidResponse
        }
        return decoded
    }

    private func updateReadyState() {
        guard let configuration else {
            state = .disconnected
            return
        }
        state = .ready(
            region: configuration.regionTitle,
            scope: configuration.connectionScope
        )
    }

    private func safeMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "连接测试失败，请检查配置和网络。" : String(message.prefix(140))
    }
}

private struct QwenChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct QwenErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
    let message: String?
}

private struct QwenCoachPayload: Decodable {
    let headline: String
    let message: String
    let action: String

    func makeBrief(fallback: CoachBrief) -> CoachBrief {
        let resolvedAction = CoachAction(rawValue: action) ?? fallback.action
        let metadata: (title: String, symbol: String) = switch resolvedAction {
        case .weigh: ("去称重", "figure.stand")
        case .logMeal: ("记录下一餐", "camera.fill")
        case .reviewMeals: ("查看饮食", "viewfinder")
        case .viewProgress: ("查看趋势", "chart.xyaxis.line")
        case .none: ("知道了", "checkmark.circle.fill")
        }
        let cleanHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return CoachBrief(
            headline: cleanHeadline.isEmpty ? fallback.headline : String(cleanHeadline.prefix(24)),
            message: cleanMessage.isEmpty ? fallback.message : String(cleanMessage.prefix(120)),
            actionTitle: metadata.title,
            action: resolvedAction,
            symbol: metadata.symbol,
            source: .qwenCloud
        )
    }
}

private struct QwenWeeklyPayload: Decodable {
    let headline: String
    let summary: String
    let win: String
    let focus: String
    let nextGoal: String

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case win
        case focus
        case nextGoal = "next_goal"
    }
}

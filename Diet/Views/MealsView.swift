import SwiftData
import SwiftUI

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var qwenAIService: QwenAIService
    @Query(sort: \MealRecord.eatenAt, order: .reverse)
    private var meals: [MealRecord]

    @State private var showingAddMeal = false
    @State private var selectedMeal: MealRecord?
    @State private var isAnalyzingHistory = false
    @State private var historyProgress = 0
    @State private var historyTotal = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    summaryCard

                    if meals.isEmpty {
                        emptyState
                    } else {
                        ForEach(mealSections) { section in
                            daySection(section)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("饮食日记")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMeal = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.coral, in: Circle())
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingAddMeal) {
            AddMealView()
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailView(meal: meal) {
                selectedMeal = nil
                delete(meal)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                RoundIcon(
                    symbol: "camera.aperture",
                    foreground: AppTheme.ink,
                    background: AppTheme.lime,
                    size: 52
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(todayCount) 次记录")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(todayCalorieText ?? "拍照后自动生成饮食洞察")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("连续 \(recordingStreak) 天")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(AppTheme.paleLime, in: Capsule())
                    Text("仅统计照片估算")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }

            if !pendingMeals.isEmpty || isAnalyzingHistory {
                Divider().overlay(AppTheme.divider)

                Button {
                    analyzeHistory()
                } label: {
                    HStack(spacing: 12) {
                        if isAnalyzingHistory {
                            ProgressView()
                                .tint(AppTheme.ink)
                        } else {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .foregroundStyle(AppTheme.coral)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isAnalyzingHistory ? "正在分析 \(historyProgress)/\(historyTotal)" : "分析以前的照片")
                                .font(.subheadline.weight(.semibold))
                            Text("还有 \(pendingMeals.count) 张照片没有饮食洞察")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        if !isAnalyzingHistory {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                    }
                    .foregroundStyle(AppTheme.ink)
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzingHistory)
            }
        }
        .appCard()
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.paleLime)
                    .frame(width: 112, height: 112)
                Image(systemName: "camera.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            Text("拍下第一餐")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            Text("照片会在本机识别食物，生成热量区间和下一餐建议。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("记录饮食") {
                showingAddMeal = true
            }
            .buttonStyle(FilledActionButtonStyle(color: AppTheme.coral))
            .frame(maxWidth: 230)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

    private func daySection(_ section: MealDaySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(section.day))
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("\(section.meals.count) 餐")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                if let range = calorieRange(for: section.meals) {
                    Text("约 \(range.lowerBound)–\(range.upperBound) 千卡")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }

            ForEach(section.meals) { meal in
                mealStoryCard(meal)
                    .onTapGesture { selectedMeal = meal }
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(meal)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func mealStoryCard(_ meal: MealRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                MealPhoto(data: meal.photoData, height: 220)

                LinearGradient(
                    colors: [.clear, AppTheme.ink.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(meal.mealType.title, systemImage: meal.mealType.symbol)
                            .font(.headline)
                        Text(meal.eatenAt, format: .dateTime.hour().minute())
                            .font(.caption)
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    Text(meal.calorieRangeText ?? (meal.hasAnalysis ? "待确认" : "待分析"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(meal.hasAnalysis ? AppTheme.ink : .white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            meal.hasAnalysis ? AnyShapeStyle(AppTheme.lime) : AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule()
                        )
                }
                .padding(16)
            }
            .frame(height: 220)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                if meal.hasAnalysis {
                    HStack(spacing: 7) {
                        ForEach(meal.analysisTags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(AppTheme.paleLime, in: Capsule())
                        }
                        Spacer()
                        if let score = meal.nutritionScore {
                            Label("\(score)", systemImage: "leaf.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.mint)
                        }
                        if meal.isUserCorrected {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                                .accessibilityLabel("已按你的确认更新")
                        }
                    }

                    Text(meal.analysisSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(2)
                } else {
                    Label("点开后可用 Apple Vision 分析这张照片", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                if !meal.note.isEmpty {
                    Text(meal.note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(2)
                }
            }
            .padding(15)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.ink.opacity(0.055), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var mealSections: [MealDaySection] {
        Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.eatenAt) }
            .map { MealDaySection(day: $0.key, meals: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var pendingMeals: [MealRecord] {
        meals.filter { !$0.hasAnalysis && $0.photoData != nil }
    }

    private var todayCount: Int {
        meals.filter { Calendar.current.isDateInToday($0.eatenAt) }.count
    }

    private var todayCalorieText: String? {
        guard let range = calorieRange(
            for: meals.filter { Calendar.current.isDateInToday($0.eatenAt) }
        ) else {
            return nil
        }
        return "今日约 \(range.lowerBound)–\(range.upperBound) 千卡"
    }

    private var recordingStreak: Int {
        let days = Set(meals.map { Calendar.current.startOfDay(for: $0.eatenAt) })
        var streak = 0
        var date = Calendar.current.startOfDay(for: .now)
        while days.contains(date) {
            streak += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) else {
                break
            }
            date = previous
        }
        return streak
    }

    private func calorieRange(for records: [MealRecord]) -> ClosedRange<Int>? {
        let lows = records.compactMap(\.estimatedCaloriesLow)
        let highs = records.compactMap(\.estimatedCaloriesHigh)
        guard !lows.isEmpty, !highs.isEmpty else { return nil }
        return lows.reduce(0, +)...highs.reduce(0, +)
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.wide).day())
    }

    private func analyzeHistory() {
        guard !isAnalyzingHistory else { return }
        let candidates = pendingMeals
        guard !candidates.isEmpty else { return }

        isAnalyzingHistory = true
        historyProgress = 0
        historyTotal = candidates.count

        Task {
            for (index, meal) in candidates.enumerated() {
                historyProgress = index + 1
                guard let data = meal.photoData else { continue }
                if let analysis = try? await qwenAIService.analyzeMealWithFallback(
                    imageData: data,
                    portion: meal.portion
                ) {
                    meal.apply(analysis, portion: meal.portion)
                }
            }
            try? modelContext.save()
            isAnalyzingHistory = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func delete(_ meal: MealRecord) {
        modelContext.delete(meal)
        try? modelContext.save()
    }
}

private struct MealDaySection: Identifiable {
    let day: Date
    let meals: [MealRecord]

    var id: Date { day }
}

private struct MealDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var qwenAIService: QwenAIService

    let meal: MealRecord
    let delete: () -> Void

    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var showingCorrection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MealPhoto(data: meal.photoData, height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label(meal.mealType.title, systemImage: meal.mealType.symbol)
                            .font(.title2.bold())
                        Spacer()
                        Text(meal.portion.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.paleLime, in: Capsule())
                    }
                    Text(meal.eatenAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    if !meal.note.isEmpty {
                        Text(meal.note)
                            .font(.body)
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(AppTheme.ink)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionTitle(title: "AI 饮食分析")
                        Spacer()
                        Label(
                            meal.isUserCorrected
                                ? "你已确认"
                                : (qwenAIService.isConfigured ? "Qwen 优先" : "本机完成"),
                            systemImage: meal.isUserCorrected
                                ? "checkmark.seal.fill"
                                : (qwenAIService.isConfigured ? "sparkles" : "lock.fill")
                        )
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    if isAnalyzing {
                        HStack(spacing: 12) {
                            ProgressView().tint(AppTheme.ink)
                            Text("正在分析照片…")
                                .font(.subheadline.weight(.semibold))
                        }
                    } else if meal.hasAnalysis {
                        MealAnalysisSummaryView(meal: meal)
                    } else {
                        Text("这是一条旧记录，还没有分析结果。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    if let analysisError {
                        Text(analysisError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }

                    if meal.hasAnalysis,
                       !meal.isUserCorrected,
                       (meal.analysisConfidence ?? 1) < 0.25 {
                        Label("这张照片识别把握较低，建议花几秒确认一下。", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }

                    HStack(spacing: 10) {
                        if meal.hasAnalysis {
                            Button {
                                showingCorrection = true
                            } label: {
                                Label("调整结果", systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.paleLime, in: RoundedRectangle(cornerRadius: 15))
                            }
                        }

                        Button {
                            analyze()
                        } label: {
                            Label(meal.hasAnalysis ? "重新分析" : "分析照片", systemImage: "viewfinder")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .buttonStyle(.plain)
                    .disabled(isAnalyzing || meal.photoData == nil)

                    Text("热量为照片和份量推算的范围，只用于趋势参考。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .appCard()

                Button(role: .destructive, action: delete) {
                    Label("删除这条记录", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .sheet(isPresented: $showingCorrection) {
            MealCorrectionSheet(meal: meal)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func analyze() {
        guard let data = meal.photoData else { return }
        isAnalyzing = true
        analysisError = nil

        Task {
            do {
                let result = try await qwenAIService.analyzeMealWithFallback(
                    imageData: data,
                    portion: meal.portion
                )
                meal.apply(result, portion: meal.portion)
                try modelContext.save()
            } catch {
                analysisError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

private struct MealCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let meal: MealRecord

    @State private var tags: [String]
    @State private var newTag = ""
    @State private var selectedGroups: Set<FoodGroup>
    @State private var portion: MealPortion
    @State private var caloriesLow: Int
    @State private var caloriesHigh: Int

    init(meal: MealRecord) {
        self.meal = meal
        _tags = State(initialValue: meal.analysisTags)
        _selectedGroups = State(initialValue: Set(meal.analysisGroups))
        _portion = State(initialValue: meal.portion)
        _caloriesLow = State(initialValue: meal.estimatedCaloriesLow ?? 200)
        _caloriesHigh = State(initialValue: meal.estimatedCaloriesHigh ?? 500)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    editorSection(
                        title: "识别到的食物",
                        subtitle: "删掉错误标签，也可以补上照片里没认出的食物。"
                    ) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 82), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(tag).lineLimit(1)
                                        Image(systemName: "xmark")
                                            .font(.caption2.bold())
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(AppTheme.paleLime, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("补充食物，例如：青菜", text: $newTag)
                                .textInputAutocapitalization(.never)
                                .submitLabel(.done)
                                .onSubmit(addTag)
                            Button(action: addTag) {
                                Image(systemName: "plus")
                                    .font(.subheadline.bold())
                                    .frame(width: 36, height: 36)
                                    .background(AppTheme.paleLime, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(cleanedNewTag.isEmpty)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15))
                    }

                    editorSection(
                        title: "餐盘结构",
                        subtitle: "可多选；这会影响餐盘评分和教练建议。"
                    ) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(FoodGroup.allCases) { group in
                                let isSelected = selectedGroups.contains(group)
                                Button {
                                    if isSelected {
                                        selectedGroups.remove(group)
                                    } else {
                                        selectedGroups.insert(group)
                                    }
                                } label: {
                                    Text(group.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            isSelected ? AppTheme.ink : AppTheme.background,
                                            in: RoundedRectangle(cornerRadius: 13)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    editorSection(
                        title: "份量与热量范围",
                        subtitle: "按你实际吃下的量调整；不用追求精确到个位数。"
                    ) {
                        Picker("份量", selection: $portion) {
                            ForEach(MealPortion.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: portion) { oldValue, newValue in
                            rescaleCalories(from: oldValue, to: newValue)
                        }

                        HStack(spacing: 12) {
                            calorieField(title: "下限", value: $caloriesLow)
                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.secondaryInk)
                            calorieField(title: "上限", value: $caloriesHigh)
                        }
                    }

                    Label(
                        "保存后，这类照片会优先采用你的确认结果；所有学习只保存在本机。",
                        systemImage: "brain.head.profile"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("调整识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func editorSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            content()
        }
        .appCard()
    }

    private func calorieField(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
            HStack(spacing: 4) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("千卡")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .padding(12)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var cleanedNewTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !tags.isEmpty
            && !selectedGroups.isEmpty
            && caloriesLow >= 0
            && caloriesHigh >= caloriesLow
            && caloriesHigh <= 4_000
    }

    private func addTag() {
        let value = String(cleanedNewTag.prefix(12))
        guard !value.isEmpty, !tags.contains(value) else {
            newTag = ""
            return
        }
        tags.append(value)
        newTag = ""
    }

    private func rescaleCalories(from oldPortion: MealPortion, to newPortion: MealPortion) {
        let ratio = newPortion.factor / max(oldPortion.factor, 0.01)
        caloriesLow = max(0, Int((Double(caloriesLow) * ratio / 10).rounded() * 10))
        caloriesHigh = max(caloriesLow, Int((Double(caloriesHigh) * ratio / 10).rounded() * 10))
    }

    private func save() {
        meal.applyCorrection(
            tags: tags,
            groups: FoodGroup.allCases.filter(selectedGroups.contains),
            portion: portion,
            caloriesLow: caloriesLow,
            caloriesHigh: caloriesHigh
        )
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var scaleManager: BluetoothScaleManager
    @EnvironmentObject private var aiManager: OnDeviceAIManager
    @EnvironmentObject private var qwenAIService: QwenAIService
    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var weights: [WeightRecord]
    @Query(sort: \MealRecord.eatenAt, order: .reverse)
    private var meals: [MealRecord]

    @AppStorage("profileName") private var profileName = ""
    @AppStorage("targetWeight") private var targetWeight = 65.0
    @State private var showingWeightEntry = false
    @State private var showingMealEntry = false
    @State private var showingScale = false
    @State private var coachBrief: CoachBrief?
    @State private var isRefreshingCoach = false
    @State private var showingWeeklyReport = false
    @State private var cloudWeeklyReport: WeeklyCoachReport?

    private var recentWeights: [WeightRecord] {
        Array(weights.prefix(14))
    }

    private var todayMeals: [MealRecord] {
        meals.filter { Calendar.current.isDateInToday($0.eatenAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    greeting
                    weightHero
                    coachCard
                    quickActions
                    trendCard
                    todayMealsSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingWeightEntry) {
            AddWeightSheet(initialWeight: weights.first?.weightKg)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingMealEntry) {
            AddMealView()
        }
        .sheet(isPresented: $showingScale) {
            ScaleConnectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWeeklyReport) {
            WeeklyCoachReportView(report: weeklyReport)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: coachRefreshKey) {
            await refreshCoach()
        }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greetingText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
                Text(profileName.isEmpty ? "今天也轻一点" : "\(profileName)，今天也轻一点")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Button {
                selectedTab = 3
            } label: {
                RoundIcon(
                    symbol: "person.fill",
                    foreground: AppTheme.ink,
                    background: Color.white,
                    size: 48
                )
                .shadow(color: AppTheme.ink.opacity(0.06), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private var weightHero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("当前体重", systemImage: "figure.stand")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.7))
                Spacer()
                Button {
                    showingScale = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scaleManager.state.isConnected ? AppTheme.mint : AppTheme.coral)
                            .frame(width: 7, height: 7)
                        Text(scaleManager.state.isConnected ? "体重秤在线" : "连接体重秤")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(currentWeightText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("kg")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
                Spacer()
                if let deltaText {
                    Label(deltaText, systemImage: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(delta <= 0 ? AppTheme.ink : AppTheme.coral)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.62), in: Capsule())
                }
            }

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.55))
                        Capsule()
                            .fill(AppTheme.ink)
                            .frame(width: proxy.size.width * goalProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("目标进度 \(Int(goalProgress * 100))%")
                    Spacer()
                    Text("目标 \(targetWeight, specifier: "%.1f") kg")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.ink.opacity(0.64))
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppTheme.lime, Color(red: 0.82, green: 0.93, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 135, height: 135)
                .offset(x: 42, y: 52)
                .allowsHitTesting(false)
        }
        .shadow(color: AppTheme.lime.opacity(0.24), radius: 24, y: 12)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction(
                title: "记录饮食",
                subtitle: "拍张照片",
                symbol: "camera.fill",
                color: AppTheme.coral
            ) {
                showingMealEntry = true
            }

            quickAction(
                title: "记录体重",
                subtitle: "手动输入",
                symbol: "plus",
                color: AppTheme.ink
            ) {
                showingWeightEntry = true
            }
        }
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label("今日 AI 教练", systemImage: "apple.intelligence")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let coachBrief {
                    Text(coachBrief.source.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.13), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(0.86))

            if isRefreshingCoach, coachBrief == nil {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("正在把今天的记录整理成下一步…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if let coachBrief {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: coachBrief.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.lime, in: Circle())

                    VStack(alignment: .leading, spacing: 7) {
                        Text(coachBrief.headline)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text(coachBrief.message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        perform(coachBrief.action)
                    } label: {
                        Text(coachBrief.actionTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.lime, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await refreshCoach() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingCoach)
                }

                Button {
                    showingWeeklyReport = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                        Text("查看本周复盘")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("只读取轻衡里的体重与饮食摘要，不上传照片")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.ink, Color(red: 0.08, green: 0.31, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: AppTheme.ink.opacity(0.16), radius: 20, y: 10)
    }

    private func quickAction(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundIcon(symbol: symbol, foreground: .white, background: color, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var trendCard: some View {
        VStack(spacing: 16) {
            SectionTitle(title: "最近趋势", actionTitle: "查看全部") {
                selectedTab = 2
            }
            if recentWeights.isEmpty {
                ContentUnavailableView(
                    "还没有体重数据",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("连接体重秤或先手动记录一次")
                )
                .frame(height: 165)
            } else {
                WeightChart(records: recentWeights, compact: true)
            }
        }
        .appCard()
    }

    private var todayMealsSection: some View {
        VStack(spacing: 14) {
            SectionTitle(title: "今日饮食", actionTitle: todayMeals.isEmpty ? nil : "全部") {
                selectedTab = 1
            }

            if todayMeals.isEmpty {
                Button {
                    showingMealEntry = true
                } label: {
                    HStack(spacing: 14) {
                        RoundIcon(symbol: "camera.fill", foreground: AppTheme.ink, background: AppTheme.paleLime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("用照片开始今天的记录")
                                .font(.subheadline.weight(.bold))
                            Text("不用计算，先培养觉察")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .appCard(padding: 15)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(todayMeals) { meal in
                            VStack(alignment: .leading, spacing: 0) {
                                MealPhoto(data: meal.photoData, height: 118)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.mealType.title)
                                        .font(.subheadline.weight(.bold))
                                    Text(meal.eatenAt, format: .dateTime.hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                                .padding(12)
                            }
                            .frame(width: 166)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var currentWeightText: String {
        guard let weight = weights.first?.weightKg else { return "—" }
        return String(format: "%.1f", weight)
    }

    private var delta: Double {
        guard weights.count > 1 else { return 0 }
        return weights[0].weightKg - weights[1].weightKg
    }

    private var deltaText: String? {
        guard weights.count > 1 else { return nil }
        return String(format: "%+.1f kg", delta)
    }

    private var goalProgress: Double {
        guard let current = weights.first?.weightKg else { return 0 }
        let start = weights.last?.weightKg ?? current
        return WeightAnalytics.progress(start: start, current: current, target: targetWeight)
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }

    private var coachRefreshKey: String {
        let latestWeight = weights.first?.id.uuidString ?? "none"
        let mealState = todayMeals
            .map { "\($0.id.uuidString):\($0.analysisVersion)" }
            .joined(separator: ",")
        return "\(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)-\(latestWeight)-\(mealState)-\(qwenAIService.isCloudReady)"
    }

    private var weeklyReport: WeeklyCoachReport {
        cloudWeeklyReport ?? WeeklyCoachEngine.makeReport(weights: weights, meals: meals)
    }

    private func refreshCoach() async {
        isRefreshingCoach = true
        let context = CoachContext.make(
            weights: weights,
            meals: meals,
            targetWeight: targetWeight
        )
        let localFallback = LocalCoachEngine.brief(for: context)
        let localReport = WeeklyCoachEngine.makeReport(weights: weights, meals: meals)
        async let enhancedReport = qwenAIService.enhanceWeeklyReport(localReport)

        let result: CoachBrief
        if let cloudBrief = await qwenAIService.coachBrief(
            for: context,
            fallback: localFallback
        ) {
            result = cloudBrief
        } else {
            result = await aiManager.coachBrief(for: context)
        }
        let resolvedWeeklyReport = await enhancedReport ?? localReport
        withAnimation(.easeOut(duration: 0.24)) {
            coachBrief = result
            cloudWeeklyReport = resolvedWeeklyReport
            isRefreshingCoach = false
        }
    }

    private func perform(_ action: CoachAction) {
        switch action {
        case .weigh:
            showingScale = true
        case .logMeal:
            showingMealEntry = true
        case .reviewMeals:
            selectedTab = 1
        case .viewProgress:
            selectedTab = 2
        case .none:
            break
        }
    }
}

private struct WeeklyCoachReportView: View {
    @Environment(\.dismiss) private var dismiss

    let report: WeeklyCoachReport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    metrics
                    reportSection(
                        title: "本周做得最好",
                        symbol: "checkmark.seal.fill",
                        color: AppTheme.mint,
                        text: report.win
                    )
                    reportSection(
                        title: "值得留意",
                        symbol: "scope",
                        color: AppTheme.coral,
                        text: report.focus
                    )
                    nextGoal

                    Text("周报只根据轻衡内最近 7 天的记录生成，用于观察习惯与趋势，不替代医疗或营养诊断。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("本周复盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(report.periodText, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title3.bold())
            }
            Text(report.headline)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppTheme.lime, Color(red: 0.75, green: 0.92, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var metrics: some View {
        HStack(spacing: 9) {
            metric(value: report.weightChangeText, label: "体重趋势", symbol: "chart.line.downtrend.xyaxis")
            metric(value: report.weightCoverageText, label: "称重", symbol: "scalemass.fill")
            metric(value: report.mealCoverageText, label: "饮食", symbol: "camera.fill")
        }
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.mint)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reportSection(
        title: String,
        symbol: String,
        color: Color,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            RoundIcon(symbol: symbol, foreground: color, background: color.opacity(0.12), size: 42)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var nextGoal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("下周只做一件事", systemImage: "flag.fill")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))
            Text(report.nextGoal)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

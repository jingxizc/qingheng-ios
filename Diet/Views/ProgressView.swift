import Charts
import SwiftData
import SwiftUI

struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var weights: [WeightRecord]

    @AppStorage("targetWeight") private var targetWeight = 65.0
    @State private var range = TimeRange.month

    private enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7天"
        case month = "30天"
        case quarter = "90天"

        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    private var filteredWeights: [WeightRecord] {
        guard let start = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) else {
            return weights
        }
        return weights.filter { $0.measuredAt >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("时间范围", selection: $range) {
                        ForEach(TimeRange.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    chartCard
                    stats
                    history
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("体重趋势")
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("变化")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(changeText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(change <= 0 ? AppTheme.ink : AppTheme.coral)
                }
                Spacer()
                Text("目标 \(targetWeight, specifier: "%.1f") kg")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(AppTheme.paleLime, in: Capsule())
            }

            if filteredWeights.isEmpty {
                ContentUnavailableView(
                    "等待第一次称重",
                    systemImage: "scalemass",
                    description: Text("记录后会在这里看到变化曲线")
                )
                .frame(height: 245)
            } else {
                Chart {
                    ForEach(filteredWeights.sorted(by: { $0.measuredAt < $1.measuredAt })) { record in
                        LineMark(
                            x: .value("日期", record.measuredAt),
                            y: .value("体重", record.weightKg)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.ink)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                        PointMark(
                            x: .value("日期", record.measuredAt),
                            y: .value("体重", record.weightKg)
                        )
                        .foregroundStyle(AppTheme.lime)
                        .symbolSize(35)
                    }

                    RuleMark(y: .value("目标", targetWeight))
                        .foregroundStyle(AppTheme.coral.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("目标")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.coral)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(format: .dateTime.month().day())
                        AxisGridLine().foregroundStyle(AppTheme.divider)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisValueLabel()
                        AxisGridLine().foregroundStyle(AppTheme.divider)
                    }
                }
                .frame(height: 250)
            }
        }
        .appCard()
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statCard(
                title: "当前",
                value: weights.first.map { String(format: "%.1f", $0.weightKg) } ?? "—",
                unit: "kg",
                symbol: "figure.stand"
            )
            statCard(
                title: "平均",
                value: WeightAnalytics.average(in: filteredWeights)
                    .map { String(format: "%.1f", $0) } ?? "—",
                unit: "kg",
                symbol: "equal"
            )
        }
    }

    private func statCard(title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            RoundIcon(symbol: symbol, size: 38)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 16)
    }

    private var history: some View {
        VStack(spacing: 4) {
            SectionTitle(title: "称重记录")
                .padding(.bottom, 8)

            if weights.isEmpty {
                Text("暂无记录")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(weights.prefix(30)) { record in
                    HStack(spacing: 12) {
                        RoundIcon(
                            symbol: record.source.symbol,
                            foreground: AppTheme.ink,
                            background: record.source == .bluetooth
                                ? AppTheme.paleLime
                                : AppTheme.background,
                            size: 40
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.measuredAt, format: .dateTime.month().day().hour().minute())
                                .font(.subheadline.weight(.semibold))
                            Text(record.sessionSummary ?? record.source.title)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        Text("\(record.weightKg, specifier: "%.1f") kg")
                            .font(.headline)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.vertical, 10)
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    if record.id != weights.prefix(30).last?.id {
                        Divider().overlay(AppTheme.divider)
                    }
                }
            }
        }
        .appCard()
    }

    private var change: Double {
        WeightAnalytics.change(in: filteredWeights) ?? 0
    }

    private var changeText: String {
        guard filteredWeights.count > 1 else { return "—" }
        return String(format: "%+.1f kg", change)
    }

    private func delete(_ record: WeightRecord) {
        let recordID = record.id
        modelContext.delete(record)
        try? modelContext.save()
        Task {
            await healthKitManager.deleteWeight(id: recordID)
        }
    }
}

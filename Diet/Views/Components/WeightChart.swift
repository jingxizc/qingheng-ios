import Charts
import SwiftUI

struct WeightChart: View {
    let records: [WeightRecord]
    var compact = false

    private var sortedRecords: [WeightRecord] {
        records.sorted { $0.measuredAt < $1.measuredAt }
    }

    var body: some View {
        Chart(sortedRecords) { record in
            AreaMark(
                x: .value("日期", record.measuredAt),
                yStart: .value("基线", minimumWeight),
                yEnd: .value("体重", record.weightKg)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [AppTheme.lime.opacity(0.42), AppTheme.lime.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("日期", record.measuredAt),
                y: .value("体重", record.weightKg)
            )
            .foregroundStyle(AppTheme.ink)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if record.id == sortedRecords.last?.id {
                PointMark(
                    x: .value("日期", record.measuredAt),
                    y: .value("体重", record.weightKg)
                )
                .foregroundStyle(AppTheme.coral)
                .symbolSize(55)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 4 : 6)) {
                AxisValueLabel(format: .dateTime.month().day())
                    .foregroundStyle(AppTheme.secondaryInk)
                AxisGridLine().foregroundStyle(AppTheme.divider)
                AxisTick().foregroundStyle(.clear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
                    .foregroundStyle(AppTheme.secondaryInk)
                AxisGridLine().foregroundStyle(AppTheme.divider)
                AxisTick().foregroundStyle(.clear)
            }
        }
        .chartYScale(domain: yDomain)
        .frame(height: compact ? 150 : 245)
    }

    private var minimumWeight: Double {
        max((sortedRecords.map(\.weightKg).min() ?? 60) - 1.5, 0)
    }

    private var yDomain: ClosedRange<Double> {
        let values = sortedRecords.map(\.weightKg)
        let low = max((values.min() ?? 60) - 2, 0)
        let high = max((values.max() ?? 70) + 2, low + 5)
        return low...high
    }
}

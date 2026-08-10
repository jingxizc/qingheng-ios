import SwiftData
import SwiftUI

struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = false

    @State private var weightText: String
    @State private var measuredAt = Date()

    init(initialWeight: Double?) {
        _weightText = State(
            initialValue: initialWeight.map { String(format: "%.1f", $0) } ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 7) {
                    Text("这次多少？")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("手动记录也会进入同一条趋势线")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    TextField("0.0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 180)
                    Text("kg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(AppTheme.paleLime, in: RoundedRectangle(cornerRadius: 26))

                DatePicker(
                    "称重时间",
                    selection: $measuredAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline.weight(.semibold))

                Button("保存体重") {
                    save()
                }
                .buttonStyle(FilledActionButtonStyle())
                .disabled(parsedWeight == nil)
                .opacity(parsedWeight == nil ? 0.45 : 1)
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
    }

    private var parsedWeight: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let weight = Double(normalized), (10...350).contains(weight) else { return nil }
        return weight
    }

    private func save() {
        guard let parsedWeight else { return }
        let record = WeightRecord(
            weightKg: parsedWeight,
            measuredAt: measuredAt,
            source: .manual
        )
        modelContext.insert(record)
        try? modelContext.save()
        if healthKitSyncEnabled {
            Task {
                await healthKitManager.saveWeight(record)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

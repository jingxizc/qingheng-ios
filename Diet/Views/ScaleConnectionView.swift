import SwiftUI

struct ScaleConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scaleManager: BluetoothScaleManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    scaleVisual

                    VStack(spacing: 6) {
                        Text(weightText)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .contentTransition(.numericText())
                        Text(scaleManager.liveWeightKg == nil ? scaleManager.state.title : "保持站立，等待数字稳定")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }

                    if !scaleManager.devices.isEmpty,
                       !scaleManager.state.isConnected {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("站上你自己的秤，再选择信号最强的设备")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryInk)

                            ForEach(scaleManager.devices) { device in
                                Button {
                                    scaleManager.connect(to: device)
                                } label: {
                                    HStack {
                                        RoundIcon(symbol: "scalemass.fill", size: 40)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(device.name)
                                                .font(.subheadline.weight(.bold))
                                            Text("\(signalText(device.rssi)) · ID \(device.id.uuidString.suffix(4))")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryInk)
                                        }
                                        Spacer()
                                        Text("连接")
                                            .font(.caption.weight(.bold))
                                    }
                                    .foregroundStyle(AppTheme.ink)
                                    .appCard(padding: 13)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        instructionRow(number: "1", text: "首次使用先选择并绑定你自己的秤")
                        instructionRow(number: "2", text: "赤脚站上体重秤并保持不动")
                        instructionRow(number: "3", text: "读数稳定后会自动保存")
                    }
                    .appCard()

                    if scaleManager.connectedDeviceName != nil {
                        Button("忘记这台体重秤", role: .destructive) {
                            scaleManager.forgetScale()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("连接体重秤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(AppTheme.ink)
                }
            }
            .onAppear {
                scaleManager.startMonitoring()
            }
        }
    }

    private var scaleVisual: some View {
        ZStack {
            Circle()
                .fill(AppTheme.lime.opacity(0.18))
                .frame(width: 190, height: 190)
                .scaleEffect(scaleManager.state == .scanning ? 1.08 : 0.95)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: scaleManager.state == .scanning
                )
            Circle()
                .fill(AppTheme.lime.opacity(0.34))
                .frame(width: 148, height: 148)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .frame(width: 112, height: 112)
                .shadow(color: AppTheme.ink.opacity(0.1), radius: 18, y: 9)
            Image(systemName: "scalemass.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.top, 8)
    }

    private var weightText: String {
        guard let liveWeightKg = scaleManager.liveWeightKg else { return "— kg" }
        return String(format: "%.1f kg", liveWeightKg)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ink)
                .frame(width: 27, height: 27)
                .background(AppTheme.paleLime, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func signalText(_ rssi: Int) -> String {
        switch rssi {
        case -60...0: "信号很好"
        case -75 ..< -60: "信号良好"
        default: "请靠近体重秤"
        }
    }
}

import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var scaleManager: BluetoothScaleManager
    @EnvironmentObject private var aiManager: OnDeviceAIManager
    @EnvironmentObject private var qwenAIService: QwenAIService
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var coachNotificationManager: CoachNotificationManager
    @Query(sort: \WeightRecord.measuredAt, order: .reverse)
    private var weights: [WeightRecord]
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("targetWeight") private var targetWeight = 65.0
    @AppStorage("heightCM") private var heightCM = 170.0
    @AppStorage("autoBluetoothSync") private var autoBluetoothSync = true
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = false
    @AppStorage("coachRemindersEnabled") private var coachRemindersEnabled = false
    @AppStorage("coachReminderHour") private var coachReminderHour = 20
    @AppStorage("coachReminderMinute") private var coachReminderMinute = 30

    @State private var showingScale = false
    @State private var showingQwenConnection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    scaleCard
                    goalsCard
                    reminderCard
                    healthKitCard
                    aiCard
                    privacyCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("我的")
        }
        .sheet(isPresented: $showingScale) {
            ScaleConnectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingQwenConnection) {
            QwenConnectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await coachNotificationManager.refreshAuthorizationStatus()
            if coachNotificationManager.state == .denied {
                coachRemindersEnabled = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await coachNotificationManager.refreshAuthorizationStatus()
                if coachNotificationManager.state == .denied {
                    coachRemindersEnabled = false
                }
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.lime, AppTheme.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "figure.walk")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 7) {
                TextField("你的称呼", text: $profileName)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("每一次记录，都算数")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var scaleCard: some View {
        VStack(spacing: 16) {
            SectionTitle(title: "智能体重秤")
            Button {
                showingScale = true
            } label: {
                HStack(spacing: 14) {
                    RoundIcon(
                        symbol: "scalemass.fill",
                        foreground: AppTheme.ink,
                        background: AppTheme.paleLime,
                        size: 50
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scaleManager.connectedDeviceName ?? "小米体重秤")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(scaleManager.state.title)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .buttonStyle(.plain)

            Divider().overlay(AppTheme.divider)

            Toggle(isOn: $autoBluetoothSync) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动同步")
                        .font(.subheadline.weight(.semibold))
                    Text("站上体重秤后自动保存稳定读数")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .tint(AppTheme.mint)
        }
        .appCard()
    }

    private var goalsCard: some View {
        VStack(spacing: 18) {
            SectionTitle(title: "身体与目标")
            settingRow(title: "目标体重", symbol: "target") {
                HStack(spacing: 4) {
                    TextField("65", value: $targetWeight, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("kg")
                }
            }
            Divider().overlay(AppTheme.divider)
            settingRow(title: "身高", symbol: "ruler") {
                HStack(spacing: 4) {
                    TextField("170", value: $heightCM, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("cm")
                }
            }
        }
        .appCard()
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "云端 AI")

            HStack(alignment: .top, spacing: 14) {
                RoundIcon(
                    symbol: qwenAIService.state.symbol,
                    foreground: AppTheme.ink,
                    background: aiStatusBackground,
                    size: 50
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(qwenAIService.state.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(qwenAIService.state.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if qwenAIService.state.isBusy {
                    ProgressView()
                        .tint(AppTheme.ink)
                }
            }

            Button {
                showingQwenConnection = true
            } label: {
                Label(
                    qwenAIService.isConfigured ? "管理连接" : "扫描配置二维码",
                    systemImage: qwenAIService.isConfigured ? "slider.horizontal.3" : "qrcode.viewfinder"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(qwenAIService.state.isBusy)

            Divider().overlay(AppTheme.divider)

            VStack(alignment: .leading, spacing: 7) {
                Label("本地降级：\(aiManager.state.title)", systemImage: aiManager.state.symbol)
                    .foregroundStyle(AppTheme.ink)
                Text("连接后，饮食照片、今日建议和周报优先使用 Qwen；断网或接口异常时自动回退到 Apple Vision、Apple 端侧模型和本地规则。")
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "教练提醒")

            HStack(alignment: .top, spacing: 14) {
                RoundIcon(
                    symbol: coachNotificationManager.state.symbol,
                    foreground: AppTheme.ink,
                    background: coachNotificationManager.state.isAuthorized
                        ? AppTheme.paleLime
                        : AppTheme.background,
                    size: 50
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(coachNotificationManager.state.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(coachNotificationManager.state.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if coachNotificationManager.state == .requesting {
                    ProgressView().tint(AppTheme.ink)
                }
            }

            Toggle(isOn: coachReminderBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自适应每日提醒")
                        .font(.subheadline.weight(.semibold))
                    Text("根据是否称重、记录饮食和本周趋势选择一句提醒")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .tint(AppTheme.mint)
            .disabled(coachNotificationManager.state == .requesting)

            if coachRemindersEnabled {
                Divider().overlay(AppTheme.divider)

                DatePicker(
                    "提醒时间",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .font(.subheadline.weight(.semibold))

                Label(
                    coachNotificationManager.scheduledSummary
                        ?? "每天最多一条，周日改为本周复盘",
                    systemImage: "moon.stars.fill"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
            }

            if coachNotificationManager.state == .denied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("打开系统通知设置", systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ink)
            }

            Label("提醒内容只使用本机摘要，不会上传体重或照片", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .appCard()
    }

    private var coachReminderBinding: Binding<Bool> {
        Binding(
            get: { coachRemindersEnabled },
            set: { enabled in
                guard enabled else {
                    coachRemindersEnabled = false
                    coachNotificationManager.removeScheduledReminders()
                    return
                }

                Task {
                    let granted: Bool
                    if coachNotificationManager.state.isAuthorized {
                        granted = true
                    } else {
                        granted = await coachNotificationManager.requestAuthorization()
                    }
                    coachRemindersEnabled = granted
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: coachReminderHour,
                    minute: coachReminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { value in
                coachReminderHour = Calendar.current.component(.hour, from: value)
                coachReminderMinute = Calendar.current.component(.minute, from: value)
            }
        )
    }

    private var healthKitCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Apple 健康")

            HStack(alignment: .top, spacing: 14) {
                RoundIcon(
                    symbol: healthKitManager.state.symbol,
                    foreground: AppTheme.ink,
                    background: healthKitManager.state.isPositive
                        ? AppTheme.paleLime
                        : AppTheme.background,
                    size: 50
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(healthKitManager.state.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(healthKitManager.state.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if healthKitManager.state.isBusy {
                    ProgressView()
                        .tint(AppTheme.ink)
                }
            }

            Toggle(isOn: healthSyncBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动同步体重")
                        .font(.subheadline.weight(.semibold))
                    Text("新称重记录会由轻衡写入系统健康数据库")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .tint(AppTheme.mint)
            .disabled(healthKitManager.state == .unavailable || healthKitManager.state.isBusy)

            if healthKitManager.state == .authorized {
                Button {
                    Task {
                        await healthKitManager.syncExistingWeights(weights)
                    }
                } label: {
                    Label(
                        healthKitManager.isSyncing
                            ? "正在同步…"
                            : "同步已有记录（\(weights.count)）",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(weights.isEmpty || healthKitManager.isSyncing)
            }

            if let message = healthKitManager.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("轻衡不会读取步数、心率或其他健康数据", systemImage: "hand.raised.fill")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .appCard()
        .task {
            healthKitManager.refreshAuthorizationStatus()
            if healthKitManager.state != .authorized {
                healthKitSyncEnabled = false
            }
        }
    }

    private var healthSyncBinding: Binding<Bool> {
        Binding(
            get: { healthKitSyncEnabled },
            set: { enabled in
                guard enabled else {
                    healthKitSyncEnabled = false
                    return
                }

                Task {
                    healthKitSyncEnabled = await healthKitManager.requestAuthorization()
                }
            }
        )
    }

    private var aiStatusBackground: Color {
        if qwenAIService.state.isReady {
            return AppTheme.paleLime
        }

        switch qwenAIService.state {
        case .disconnected, .testing:
            return AppTheme.background
        case .failed:
            return AppTheme.coral.opacity(0.18)
        case .ready:
            return AppTheme.paleLime
        }
    }

    private func settingRow<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            Spacer()
            content()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .foregroundStyle(AppTheme.ink)
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundIcon(
                symbol: "lock.fill",
                foreground: AppTheme.ink,
                background: AppTheme.background,
                size: 42
            )
            VStack(alignment: .leading, spacing: 5) {
                Text("数据留在你的手机")
                    .font(.subheadline.weight(.bold))
                Text("体重和饮食照片默认只保存在本机，不需要注册账号。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(AppTheme.ink)
        .appCard()
    }
}

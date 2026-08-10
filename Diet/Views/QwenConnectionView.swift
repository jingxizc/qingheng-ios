import SwiftUI
import UIKit
import VisionKit

struct QwenConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var qwenAIService: QwenAIService

    @State private var showingScanner = false
    @State private var isConnecting = false
    @State private var localMessage: String?
    @State private var scanGeneration = 0
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if qwenAIService.isConfigured, !showingScanner {
                        connectedContent
                    } else {
                        scannerContent
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("云端 AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog(
            "移除 Qwen 连接？",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("移除连接", role: .destructive) {
                Task { await removeConnection() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除本机钥匙串中的配置，不会删除体重或饮食记录。")
        }
    }

    private var connectedContent: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top, spacing: 14) {
                    RoundIcon(
                        symbol: qwenAIService.state.symbol,
                        foreground: AppTheme.ink,
                        background: qwenAIService.state.isReady
                            ? AppTheme.paleLime
                            : AppTheme.coral.opacity(0.16),
                        size: 54
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(qwenAIService.state.title)
                            .font(.headline)
                        Text(qwenAIService.state.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if qwenAIService.state.isBusy {
                        ProgressView().tint(AppTheme.ink)
                    }
                }

                Divider().overlay(AppTheme.divider)

                HStack(spacing: 10) {
                    Button {
                        Task { await qwenAIService.testConnection() }
                    } label: {
                        Label("测试连接", systemImage: "bolt.horizontal.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.paleLime, in: RoundedRectangle(cornerRadius: 15))
                    }
                    Button {
                        Task { await beginReplacement() }
                    } label: {
                        Label("更换配置", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 15))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .buttonStyle(.plain)
                .disabled(qwenAIService.state.isBusy)
            }
            .appCard()

            VStack(alignment: .leading, spacing: 12) {
                Label("安全说明", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.bold))
                Text("API Key 使用仅限本机解锁时可读的 iOS Keychain 保存。App 不会显示、导出或写入日志；照片和分析摘要只在你主动分析时发送给千问。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()

            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                Label("移除云端 AI 连接", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            if let localMessage {
                messageView(localMessage)
            }
        }
    }

    private var scannerContent: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    RoundIcon(
                        symbol: "qrcode.viewfinder",
                        foreground: AppTheme.ink,
                        background: AppTheme.paleLime,
                        size: 50
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("扫描本地配置")
                            .font(.headline)
                        Text("密钥无需出现在输入框中")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }

                if DataScannerViewController.isSupported,
                   DataScannerViewController.isAvailable {
                    ZStack {
                        QwenQRCodeScanner { payload in
                            connect(payload)
                        }
                        .id(scanGeneration)

                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.lime, lineWidth: 3)
                            .frame(width: 226, height: 226)
                            .allowsHitTesting(false)

                        if isConnecting {
                            Color.black.opacity(0.5)
                            VStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text("正在验证配置…")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(height: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    ContentUnavailableView(
                        "扫码暂不可用",
                        systemImage: "camera.fill",
                        description: Text("可以先从剪贴板导入配置")
                    )
                    .frame(height: 250)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 24))
                }

                Text("在 Mac 项目目录运行 `./Scripts/make-qwen-qr`，只需输入千问平台的完整 API Key。二维码仅在本机临时生成。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appCard()

            Button {
                guard let payload = UIPasteboard.general.string, !payload.isEmpty else {
                    localMessage = "剪贴板中没有可用的轻衡 AI 配置。"
                    return
                }
                connect(payload)
            } label: {
                Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            if qwenAIService.isConfigured {
                Button("取消更换") {
                    showingScanner = false
                    localMessage = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
            }

            if let localMessage {
                messageView(localMessage)
            }

            Label(
                "二维码本身等同于密钥，请勿截图、保存或使用在线二维码生成网站。",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func messageView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(AppTheme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func connect(_ payload: String) {
        guard !isConnecting else { return }
        isConnecting = true
        localMessage = nil
        Task {
            do {
                try await qwenAIService.connect(qrPayload: payload)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showingScanner = false
            } catch {
                localMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                scanGeneration += 1
            }
            isConnecting = false
        }
    }

    private func beginReplacement() async {
        guard await qwenAIService.authorizeManagement() else { return }
        localMessage = nil
        showingScanner = true
    }

    private func removeConnection() async {
        guard await qwenAIService.authorizeManagement() else { return }
        do {
            try qwenAIService.removeConfiguration()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            localMessage = error.localizedDescription
        }
    }
}

private struct QwenQRCodeScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        DispatchQueue.main.async {
            try? controller.startScanning()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onPayload: (String) -> Void
        private var hasDeliveredPayload = false

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasDeliveredPayload else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue,
                      !payload.isEmpty
                else {
                    continue
                }
                hasDeliveredPayload = true
                dataScanner.stopScanning()
                onPayload(payload)
                break
            }
        }
    }
}

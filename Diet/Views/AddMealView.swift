import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var qwenAIService: QwenAIService

    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var mealType = MealType.lunch
    @State private var portion = MealPortion.regular
    @State private var note = ""
    @State private var eatenAt = Date()
    @State private var showingCamera = false
    @State private var analysis: FoodVisionAnalysis?
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoPicker
                    if imageData != nil {
                        analysisCard
                    }
                    mealTypePicker
                    detailsCard

                    Button("保存这餐") {
                        save()
                    }
                    .buttonStyle(FilledActionButtonStyle(color: AppTheme.coral))
                    .disabled(imageData == nil || isAnalyzing)
                    .opacity(imageData == nil || isAnalyzing ? 0.45 : 1)
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("记录饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                guard let data = image.jpegData(compressionQuality: 0.78) else { return }
                setImage(data)
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    return
                }
                guard let data = image.jpegData(compressionQuality: 0.78) else { return }
                setImage(data)
            }
        }
    }

    private var photoPicker: some View {
        ZStack(alignment: .bottom) {
            MealPhoto(data: imageData, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            if imageData == nil {
                VStack(spacing: 9) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32, weight: .semibold))
                    Text("拍下你正在吃的")
                        .font(.headline)
                    Text("选择照片后，由 Apple Vision 在本机分析")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .foregroundStyle(AppTheme.ink)
                .padding(.bottom, 100)
            }

            HStack(spacing: 10) {
                Button {
                    showingCamera = true
                } label: {
                    Label("拍照", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.ink)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(12)
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(title: "AI 饮食分析")
                Spacer()
                Label(
                    qwenAIService.isConfigured ? "Qwen 云端" : "Apple 本机",
                    systemImage: qwenAIService.isConfigured ? "sparkles" : "lock.fill"
                )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            Picker("份量", selection: $portion) {
                ForEach(MealPortion.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)

            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppTheme.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在识别食物与餐盘结构")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            qwenAIService.isConfigured
                                ? "照片将安全发送到千问，失败时自动本机分析"
                                : "照片不会离开这台 iPhone"
                        )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let analysis {
                MealAnalysisSummaryView(analysis: analysis, portion: portion)

                Button {
                    analyzeCurrentImage()
                } label: {
                    Label("重新分析", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryInk)
            } else if let analysisError {
                Label(analysisError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.coral)
            }

            Text("热量是根据照片类别和所选份量得到的区间估算，适合观察趋势，不等同于称重配餐。")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var mealTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases) { type in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        mealType = type
                    }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: type.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(type.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(mealType == type ? .white : AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        mealType == type ? AppTheme.ink : Color.white,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 16) {
            DatePicker(
                "用餐时间",
                selection: $eatenAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline.weight(.semibold))

            Divider().overlay(AppTheme.divider)

            HStack(alignment: .top) {
                Text("备注")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TextField("例如：七分饱", text: $note, axis: .vertical)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .lineLimit(3)
            }
        }
        .foregroundStyle(AppTheme.ink)
        .appCard()
    }

    private func save() {
        guard let imageData else { return }
        modelContext.insert(
            MealRecord(
                eatenAt: eatenAt,
                mealType: mealType,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                photoData: imageData,
                portion: portion,
                analysis: analysis
            )
        )
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func setImage(_ data: Data) {
        imageData = data
        analysis = nil
        analysisError = nil
        analyzeCurrentImage()
    }

    private func analyzeCurrentImage() {
        guard let data = imageData else { return }
        isAnalyzing = true
        analysisError = nil

        Task {
            do {
                let result = try await qwenAIService.analyzeMealWithFallback(
                    imageData: data,
                    portion: portion
                )
                guard imageData == data else { return }
                analysis = result
            } catch {
                guard imageData == data else { return }
                analysis = nil
                analysisError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

struct MealAnalysisSummaryView: View {
    let tags: [String]
    let calorieText: String?
    let score: Int?
    let summary: String

    init(analysis: FoodVisionAnalysis, portion: MealPortion) {
        tags = analysis.tags
        if let range = analysis.calorieRange(for: portion) {
            calorieText = "\(range.lowerBound)–\(range.upperBound) 千卡"
        } else {
            calorieText = nil
        }
        score = analysis.nutritionScore
        summary = analysis.summary
    }

    init(meal: MealRecord) {
        tags = meal.analysisTags
        calorieText = meal.calorieRangeText
        score = meal.nutritionScore
        summary = meal.analysisSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                metric(
                    value: calorieText ?? "暂未识别",
                    label: "照片估算",
                    symbol: "flame.fill",
                    color: AppTheme.coral
                )

                if let score {
                    metric(
                        value: "\(score) 分",
                        label: "餐盘结构",
                        symbol: "leaf.fill",
                        color: AppTheme.mint
                    )
                }
            }

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(AppTheme.paleLime, in: Capsule())
                        }
                    }
                }
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metric(
        value: String,
        label: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

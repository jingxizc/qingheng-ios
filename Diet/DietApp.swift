import SwiftData
import SwiftUI

@main
struct DietApp: App {
    @StateObject private var scaleManager = BluetoothScaleManager()
    @StateObject private var aiManager = OnDeviceAIManager()
    @StateObject private var qwenAIService = QwenAIService()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var coachNotificationManager = CoachNotificationManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(scaleManager)
                .environmentObject(aiManager)
                .environmentObject(qwenAIService)
                .environmentObject(healthKitManager)
                .environmentObject(coachNotificationManager)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [WeightRecord.self, MealRecord.self])
    }
}

import Foundation
import AppIntents
import PlateCore

struct RemainingCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories remaining"
    static let description = IntentDescription("Check today's remaining calories and protein in Plate.")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let snapshot = SharedSnapshot.read() else { return .result(value: 0, dialog: "Open Plate and set your goals first.") }
        let value = Int(snapshot.targets.calories - snapshot.eaten.calories)
        if value >= 0 { return .result(value: value, dialog: "You have \(value) calories left today.") }
        return .result(value: value, dialog: "You are \(-value) calories over today's target. Tomorrow's target is unchanged.")
    }
}
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a meal"
    static let description = IntentDescription("Open Plate's meal camera.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedSnapshot.appGroup)?.set(true, forKey: "openCapture")
        NotificationCenter.default.post(name: .plateCapture, object: nil)
        return .result()
    }
}
extension Notification.Name { static let plateCapture = Notification.Name("PlateCapture") }
struct PlateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMealIntent(), phrases: ["Log a meal in \(.applicationName)"], shortTitle: "Log a meal", systemImageName: "camera")
        AppShortcut(intent: RemainingCaloriesIntent(), phrases: ["How many calories do I have left in \(.applicationName)?"], shortTitle: "Calories left", systemImageName: "flame")
    }
}

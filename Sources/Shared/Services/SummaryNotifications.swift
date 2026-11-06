import Foundation
import UserNotifications
@MainActor enum SummaryNotifications {
    static func request() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    static func schedule(store: MealStore) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["plate-summary"])
        guard store.account.settings.summaryEnabled else { return }
        var components = Calendar.current.dateComponents([.year,.month,.day], from: .now)
        components.hour = store.account.settings.summaryHour; components.minute = 0
        guard let date = Calendar.current.date(from: components), date > .now else { return }
        let totals = store.todayTotal
        let content = UNMutableNotificationContent()
        content.title = "Your plate today"
        content.body = "\(Int(totals.calories)) kcal · \(Int(totals.protein)) g protein. \(store.guidance.title). Open Plate for your full summary."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "plate-summary", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

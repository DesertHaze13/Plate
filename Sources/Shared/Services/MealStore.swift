import Foundation
import Observation
import WidgetKit
import PlateCore

struct AccountState: Codable {
    var profile = Profile()
    var targets = NutritionCalculator.targets(for: Profile())
    var settings = AppSettings()
    var foods: [SavedFood] = []
    var weights: [WeightEntry] = []
    var onboarded = false
}
@MainActor @Observable final class MealStore {
    private(set) var meals: [Meal] = []
    private(set) var error: String?
    private(set) var accountID: String?
    var account = AccountState()
    private(set) var clock = Date.now
    var trainingToday: Bool {
        get { (account.settings.trainingDayKeys ?? []).contains(DayKey.make(clock)) }
        set {
            var keys = Set(account.settings.trainingDayKeys ?? [])
            if newValue { keys.insert(DayKey.make(clock)) } else { keys.remove(DayKey.make(clock)) }
            account.settings.trainingDayKeys = keys.sorted(); persistAccount()
        }
    }
    func refreshClock() {
        let changedDay = DayKey.make(clock) != DayKey.make(.now)
        clock = .now
        if changedDay { publishWidget() }
    }
    var targets: Targets { get { account.targets } set { account.targets = newValue } }
    var effectiveTargets: Targets { trainingToday ? account.settings.trainingDayTargets ?? targets : targets }
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Plate", directoryHint: .isDirectory)
        load(account: nil)
    }
    private var file: URL { directory.appending(path: "meals-\(accountID ?? "local").json") }
    private var settingsFile: URL { directory.appending(path: "settings-\(accountID ?? "local").json") }
    func load(account: String?) {
        accountID = account; meals = []; self.account = AccountState(); error = nil
        do {
            if FileManager.default.fileExists(atPath: file.path) { meals = try JSONDecoder().decode([Meal].self, from: Data(contentsOf: file)) }
            if FileManager.default.fileExists(atPath: settingsFile.path) { self.account = try JSONDecoder().decode(AccountState.self, from: Data(contentsOf: settingsFile)) }
        } catch { self.error = "Could not read saved data: \(error.localizedDescription)" }
        publishWidget()
    }
    func replaceFromCloud(_ incoming: [Meal]) { meals = incoming.sorted { $0.timestamp > $1.timestamp }; persist() }
    func save(_ meal: Meal) {
        guard meal.isValid else { error = "Check the meal name, quantity and nutrition values."; return }
        meals.removeAll { $0.id == meal.id }; meals.append(meal)
        meals.sort { $0.timestamp > $1.timestamp }; persist()
    }
    func remove(_ id: String) { meals.removeAll { $0.id == id }; persist() }
    func persistAccount() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(account).write(to: settingsFile, options: .atomic)
            error = nil; publishWidget()
        } catch { self.error = "Could not save your preferences: \(error.localizedDescription)" }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(meals).write(to: file, options: .atomic)
            error = nil; publishWidget()
        } catch { self.error = "Could not save meals: \(error.localizedDescription)" }
    }
    func publishWidget() {
        let snapshot = SharedSnapshot(dayKey: DayKey.make(.now), eaten: todayTotal, targets: effectiveTargets.nutrients)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults(suiteName: SharedSnapshot.appGroup)?.set(data, forKey: "todaySnapshot") }
        WidgetCenter.shared.reloadAllTimelines()
    }
    var today: [Meal] { meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: clock) } }
    var todayTotal: Nutrients { today.reduce(.zero) { $0 + $1.total } }
    var guidance: DailyGuidance { DailyGuidance(eaten: todayTotal, target: effectiveTargets) }
    func saveFood(_ item: FoodItem, barcode: String? = nil) {
        if let index = account.foods.firstIndex(where: { (barcode != nil && $0.barcode == barcode) || $0.item.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }) {
            account.foods[index].item = item; account.foods[index].updatedAt = .now
        } else { account.foods.append(SavedFood(item: item, barcode: barcode)) }
        persistAccount()
    }
}

import Foundation

public struct Nutrients: Codable, Equatable, Sendable {
    public var calories, protein, carbs, fat, fiber, sugar: Double
    public init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0, sugar: Double = 0) {
        self.calories = calories; self.protein = protein; self.carbs = carbs
        self.fat = fat; self.fiber = fiber; self.sugar = sugar
    }
    public static let zero = Nutrients()
    public static func + (a: Self, b: Self) -> Self {
        .init(calories: a.calories+b.calories, protein: a.protein+b.protein, carbs: a.carbs+b.carbs, fat: a.fat+b.fat, fiber: a.fiber+b.fiber, sugar: a.sugar+b.sugar)
    }
    public func scaled(by n: Double) -> Self {
        .init(calories: calories*n, protein: protein*n, carbs: carbs*n, fat: fat*n, fiber: fiber*n, sugar: sugar*n)
    }
    public var isValid: Bool { [calories, protein, carbs, fat, fiber, sugar].allSatisfy { $0.isFinite && $0 >= 0 } }
}
public enum FoodCategory: String, Codable, CaseIterable, Sendable { case protein, carbs, fats, vegetables, fruit, dairy, drinks, snacks, sauces }
public enum MealSource: String, Codable, Sendable { case appleIntelligence, cloud, manual, barcode, label }
public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack
    public static func guess(at date: Date, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) { case 5..<11: .breakfast; case 11..<15: .lunch; case 17..<22: .dinner; default: .snack }
    }
}
public struct FoodItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var name: String
    public var category: FoodCategory
    public var servingDescription: String
    /// Nutrients for ONE base serving. Never overwrite when changing quantity.
    public var nutrients: Nutrients
    public var quantity: Double
    public var bounds: FoodBounds?
    public var needsReviewFields: [String]?
    public var confidence: Double?
    public var aiModel: String?
    public var source: MealSource
    public var total: Nutrients { nutrients.scaled(by: quantity) }
    public init(name: String, category: FoodCategory, servingDescription: String, nutrients: Nutrients, quantity: Double = 1, confidence: Double? = nil, source: MealSource = .manual) {
        self.name = name; self.category = category; self.servingDescription = servingDescription
        self.nutrients = nutrients; self.quantity = quantity; self.confidence = confidence; self.source = source
    }
}
public struct Meal: Identifiable, Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var timestamp: Date
    public var dayKey: String
    public var timeZoneID: String
    public var type: MealType
    public var items: [FoodItem]
    public var source: MealSource
    public var photoPath: String?
    public var thumbnailPath: String?
    public var updatedAt: Date = .now
    public var total: Nutrients { items.reduce(.zero) { $0 + $1.total } }
    public init(timestamp: Date = .now, items: [FoodItem], source: MealSource = .manual, calendar: Calendar = .current) {
        self.timestamp = timestamp; self.items = items; self.source = source
        self.type = MealType.guess(at: timestamp, calendar: calendar)
        self.dayKey = DayKey.make(timestamp, calendar: calendar); self.timeZoneID = calendar.timeZone.identifier
    }
    public var isValid: Bool { !items.isEmpty && items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.nutrients.isValid && $0.quantity.isFinite && $0.quantity > 0 } }
}
public enum DayKey {
    public static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
public enum Goal: String, Codable, CaseIterable, Sendable { case leanBulk, recomp, cut }
public struct Profile: Codable, Sendable {
    public var age: Int = 30
    public var male: Bool = true
    public var heightCM: Double = 175
    public var weightKG: Double = 75
    public var activityMultiplier: Double = 1.55
    public var trainingDays: Int = 4
    public var goal: Goal = .recomp
    public init() {}
}
public struct Targets: Codable, Equatable, Sendable {
    public var nutrients: Nutrients
    public var warningFraction: Double = 0.85
    public var tolerance: Double = 50
    public init(nutrients: Nutrients, warningFraction: Double = 0.85, tolerance: Double = 50) { self.nutrients = nutrients; self.warningFraction = warningFraction; self.tolerance = tolerance }
}
public struct WeightEntry: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var timestamp: Date
    public var kilograms: Double
    public init(timestamp: Date = .now, kilograms: Double) { self.timestamp = timestamp; self.kilograms = kilograms }
}
public struct SavedFood: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var item: FoodItem
    public var barcode: String?
    public var updatedAt: Date
    public init(item: FoodItem, barcode: String? = nil) { self.item = item; self.barcode = barcode; self.updatedAt = .now }
}
public struct AppSettings: Codable, Sendable {
    public var metric = true
    public var summaryEnabled = false
    public var summaryHour = 21
    public var trainingDayTargets: Targets?
    public var trainingDayKeys: [String]?
    public init() {}
}
public enum NutritionCalculator {
    public static func targets(for p: Profile) -> Targets {
        let bmr = 10*p.weightKG + 6.25*p.heightCM - 5*Double(p.age) + (p.male ? 5 : -161)
        let adjustment = p.goal == .leanBulk ? 1.10 : p.goal == .cut ? 0.825 : 1
        let kcal = max(0, bmr * p.activityMultiplier * adjustment)
        let protein = p.weightKG * 2
        let fat = kcal * 0.25 / 9
        return Targets(nutrients: .init(calories: kcal, protein: protein, carbs: max(0, (kcal-protein*4-fat*9)/4), fat: fat))
    }
}

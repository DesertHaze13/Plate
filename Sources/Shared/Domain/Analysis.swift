import Foundation

public struct FoodBounds: Codable, Equatable, Sendable {
    /// Normalized image coordinates, top-left origin.
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
}
public enum InputKind: String, Codable, Sendable { case food, label, mixed, barcode }
public enum ServingBasis: String, Codable, Sendable { case serving, per100Grams, package }
public struct LabelDetails: Codable, Sendable {
    public var basis: ServingBasis
    public var servingGrams: Double?
    public var servingsPerPackage: Double?
    public var rawText: String
    public func quantity(servings: Double) -> Double {
        switch basis { case .serving: servings; case .per100Grams: servings * (servingGrams ?? 100) / 100; case .package: servings / max(1, servingsPerPackage ?? 1) }
    }
    public var wholePackageQuantity: Double? {
        if basis == .package { return 1 }
        guard let count = servingsPerPackage else { return nil }
        return quantity(servings: count)
    }
}
public struct MealAnalysis: Codable, Sendable {
    public var kind: InputKind
    public var items: [FoodItem]
    public var label: LabelDetails?
    public var explanation: String
    public var barcode: String?
    public init(kind: InputKind, items: [FoodItem], label: LabelDetails? = nil, explanation: String, barcode: String? = nil) {
        self.kind = kind; self.items = items; self.label = label; self.explanation = explanation; self.barcode = barcode
    }
}
public enum DayStatus: String, Codable, Sendable { case calm, almost, hit, over }
public struct DailyGuidance: Sendable {
    public let state: DayStatus
    public let remaining: Double
    public let proteinRemaining: Double
    public let title: String
    public let message: String
    public init(eaten: Nutrients, target: Targets) {
        remaining = target.nutrients.calories - eaten.calories
        proteinRemaining = max(0, target.nutrients.protein - eaten.protein)
        if abs(remaining) <= target.tolerance {
            state = .hit; title = "Stop here 💪"; message = proteinRemaining > 20 ? "Calories are on target. Plan more protein into tomorrow’s meals." : "You’ve fuelled the day. Let recovery do its work."
        } else if remaining < 0 {
            state = .over; title = "You’re fuelled for today"; message = "Over by \(Int(-remaining)) kcal. Tomorrow’s target stays the same; a walk may feel good."
        } else if target.nutrients.calories > 0 && eaten.calories / target.nutrients.calories >= target.warningFraction {
            state = .almost; title = "Almost there"; message = proteinRemaining > 25 ? "\(Int(remaining)) kcal left, with \(Int(proteinRemaining)) g protein to go. Choose lean protein." : "About \(Int(remaining)) kcal left. Make it count."
        } else {
            state = .calm; title = "Room to nourish"; message = "Build your next plate around protein. You’ve got room for the rest."
        }
    }
}
public enum HistoryMath {
    public static func totals(_ meals: [Meal], on date: Date, calendar: Calendar = .current) -> Nutrients {
        meals.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }.reduce(.zero) { $0 + $1.total }
    }
    public static func streak(meals: [Meal], targets: Targets, through date: Date = .now, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date); var count = 0
        // A day in progress does not break yesterday's completed streak.
        if abs(totals(meals, on: day, calendar: calendar).calories-targets.nutrients.calories) > targets.tolerance { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        for _ in 0..<3660 {
            let mealsOnDay = meals.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            guard !mealsOnDay.isEmpty, abs(mealsOnDay.reduce(0) { $0 + $1.total.calories } - targets.nutrients.calories) <= targets.tolerance else { break }
            count += 1; day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

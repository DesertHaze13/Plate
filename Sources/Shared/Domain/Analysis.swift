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

public enum TrackedNutrient: String, CaseIterable, Identifiable, Sendable {
    case calories, protein, carbs, fat
    public var id: String { rawValue }
    public var title: String { switch self { case .calories: "Calories"; case .protein: "Protein"; case .carbs: "Carbs"; case .fat: "Fat" } }
    public var unit: String { self == .calories ? "kcal" : "g" }
    public func amount(in nutrients: Nutrients) -> Double {
        switch self { case .calories: nutrients.calories; case .protein: nutrients.protein; case .carbs: nutrients.carbs; case .fat: nutrients.fat }
    }
}
public enum TargetFillState: String, Equatable, Sendable { case under, near, met, over, unset }
/// Derived from the selected day's totals and targets; never changes food data or goals.
public struct TargetProgress: Identifiable, Equatable, Sendable {
    public let nutrient: TrackedNutrient
    public let amount: Double
    public let target: Double
    public let state: TargetFillState
    public var id: TrackedNutrient { nutrient }
    public var remaining: Double { max(0, target - amount) }
    public var excess: Double { max(0, amount - target) }
    public var fraction: Double { target > 0 ? amount / target : 0 }
    public init(nutrient: TrackedNutrient, amount: Double, target: Double, warningFraction: Double = 0.85, tolerance: Double = 0) {
        self.nutrient = nutrient
        self.amount = amount.isFinite && amount >= 0 ? amount : 0
        self.target = target.isFinite && target > 0 ? target : 0
        guard amount.isFinite, amount >= 0, target.isFinite, target > 0 else { state = .unset; return }
        let tolerance = tolerance.isFinite ? max(0, tolerance) : 0
        let threshold = warningFraction.isFinite ? min(1, max(0.5, warningFraction)) : 0.85
        if amount > target + tolerance { state = .over }
        else if abs(amount - target) <= tolerance { state = .met }
        else if amount / target >= threshold { state = .near }
        else { state = .under }
    }
    public static func all(eaten: Nutrients, targets: Targets) -> [TargetProgress] {
        TrackedNutrient.allCases.map { nutrient in
            TargetProgress(nutrient: nutrient, amount: nutrient.amount(in: eaten), target: nutrient.amount(in: targets.nutrients), warningFraction: targets.warningFraction, tolerance: nutrient == .calories ? targets.tolerance : 0)
        }
    }
}

public struct PlatePieSlice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let calories: Double
    public let grams: Double?
    public let nutrient: TrackedNutrient?
    public let category: FoodCategory?
}
public enum PieBreakdown {
    private static func safe(_ number: Double) -> Double { number.isFinite && number > 0 ? number : 0 }
    public static func macros(_ nutrients: Nutrients) -> [PlatePieSlice] {
        [TrackedNutrient.protein, .carbs, .fat].map { nutrient in
            let grams = safe(nutrient.amount(in: nutrients))
            return PlatePieSlice(id: "macro/\(nutrient.rawValue)", title: nutrient.title, calories: grams * (nutrient == .fat ? 9 : 4), grams: grams, nutrient: nutrient, category: nil)
        }
    }
    public static func foodCategories(_ meals: [Meal]) -> [PlatePieSlice] {
        FoodCategory.allCases.compactMap { category in
            let calories = meals.flatMap(\.items).filter { $0.category == category }.reduce(0) { $0 + safe($1.total.calories) }
            guard calories > 0 else { return nil }
            return PlatePieSlice(id: "food/\(category.rawValue)", title: category.rawValue.capitalized, calories: calories, grams: nil, nutrient: nil, category: category)
        }
    }
    /// Charts reports cumulative energy, not degrees. Zero-size sectors have no hit area.
    public static func slice(at energy: Double, in slices: [PlatePieSlice]) -> PlatePieSlice? {
        let visible = slices.filter { $0.calories.isFinite && $0.calories > 0 }
        let total = visible.reduce(0) { $0 + $1.calories }
        guard energy.isFinite, energy >= 0, total > 0, energy <= total else { return nil }
        var edge = 0.0
        for slice in visible {
            edge += slice.calories
            if energy < edge { return slice }
        }
        return visible.last
    }
}

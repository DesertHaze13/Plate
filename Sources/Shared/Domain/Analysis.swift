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

/// Typical caffeine per serving, used when a food has no caffeine value of its own.
public enum CaffeineEstimate {
    private static let table: [(words: [String], mg: Double)] = [
        (["decaf", "decaffeinated"], 3),
        (["matcha"], 70),
        (["cold brew"], 200),
        (["doppio", "double espresso", "double shot"], 128),
        (["espresso", "ristretto"], 64),
        (["coffee", "kopi", "latte", "cappuccino", "flat white", "americano", "mocha", "macchiato", "cortado", "affogato", "kape"], 95),
        (["monster"], 160),
        (["red bull", "energy drink", "kratingdaeng"], 80),
        (["tea", "teh", "chai", "oolong"], 47),
        (["cola", "coke", "pepsi"], 34)
    ]
    private static let coffeeWords = ["coffee", "kopi", "latte", "cappuccino", "flat white", "americano", "mocha", "macchiato", "cortado", "affogato", "kape", "espresso", "ristretto", "doppio", "cold brew", "decaf"]
    private static func normalized(_ name: String) -> String {
        " " + String(name.lowercased().map { $0.isLetter ? $0 : " " }).split(separator: " ").joined(separator: " ") + " "
    }
    /// Milligrams per serving, or nil when the name doesn't look like a caffeinated drink.
    public static func perServing(name: String) -> Double? {
        let text = normalized(name)
        return table.first { entry in entry.words.contains { word in text.contains(" \(word) ") } }?.mg
    }
    public static func isCoffee(_ name: String) -> Bool {
        let text = normalized(name)
        return coffeeWords.contains { word in text.contains(" \(word) ") }
    }
    /// The item's own caffeine when entered, otherwise the typical amount for its name.
    public static func milligrams(for item: FoodItem) -> Double {
        item.nutrients.caffeine > 0 ? item.total.caffeine : (perServing(name: item.name) ?? 0) * item.quantity
    }
}

/// Applies a reviewed AI proposal without touching unrelated foods or resurrecting a removed item.
public enum FoodReview {
    public static func applying(_ proposal: [FoodItem], replacing id: String?, to foods: [FoodItem]) -> [FoodItem] {
        guard !proposal.isEmpty else { return foods }
        guard let id else { return foods + proposal }
        guard let index = foods.firstIndex(where: { $0.id == id }) else { return foods }
        var result = foods; result.replaceSubrange(index...index, with: proposal)
        return result
    }
}

/// Budget overages are independent: a macro can exceed its target while calories are still below theirs.
public struct NutritionOverage: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let unit: String
    public let consumed: Double
    public let target: Double
    public var excess: Double { consumed - target }
    public static func evaluate(eaten: Nutrients, target: Nutrients) -> [NutritionOverage] {
        let fields: [(String, String, String, KeyPath<Nutrients, Double>)] = [
            ("calories", "Calories", "kcal", \.calories), ("protein", "Protein", "g", \.protein),
            ("carbs", "Carbs", "g", \.carbs), ("fat", "Fat", "g", \.fat)
        ]
        return fields.compactMap { id, name, unit, path in
            let value = eaten[keyPath: path], goal = target[keyPath: path]
            guard value.isFinite, goal.isFinite, goal > 0, value > goal else { return nil }
            return NutritionOverage(id: id, name: name, unit: unit, consumed: value, target: goal)
        }
    }
}

import XCTest
@testable import PlateCore
final class NutritionTests: XCTestCase {
    func testRecompositionUsesMifflinAndMacroEnergyBalances() {
        let targets = NutritionCalculator.targets(for: Profile()).nutrients
        XCTAssertEqual(targets.calories, 2633.0625, accuracy: 0.001)
        XCTAssertEqual(targets.protein, 150)
        XCTAssertEqual(targets.protein*4 + targets.carbs*4 + targets.fat*9, targets.calories, accuracy: 0.001)
    }
    func testGoalAdjustments() {
        var p = Profile(); let base = NutritionCalculator.targets(for: p).nutrients.calories
        p.goal = .leanBulk; XCTAssertEqual(NutritionCalculator.targets(for: p).nutrients.calories, base*1.1, accuracy: 0.001)
        p.goal = .cut; XCTAssertEqual(NutritionCalculator.targets(for: p).nutrients.calories, base*0.825, accuracy: 0.001)
    }
    func testServingMathDoesNotMutateBaseNutrients() {
        var item = FoodItem(name: "Rice", category: .carbs, servingDescription: "100 g", nutrients: .init(calories: 130, protein: 2.7), quantity: 0.5)
        XCTAssertEqual(item.total.calories, 65); item.quantity = 2
        XCTAssertEqual(item.total.calories, 260); XCTAssertEqual(item.nutrients.calories, 130)
    }
    func testJakartaBoundaryAndRoundTrip() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let date = ISO8601DateFormatter().date(from: "2026-11-05T18:00:00Z")!
        XCTAssertEqual(DayKey.make(date, calendar: calendar), "2026-11-06")
        let meal = Meal(timestamp: date, items: [.init(name: "Egg", category: .protein, servingDescription: "1 egg", nutrients: .init(calories: 70, protein: 6))], calendar: calendar)
        XCTAssertEqual(try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meal)), meal)
    }
    func testRejectsInvalidNutrition() {
        XCTAssertFalse(Nutrients(calories: -.infinity).isValid)
        XCTAssertFalse(Meal(items: [.init(name: "x", category: .snacks, servingDescription: "", nutrients: .zero, quantity: -1)]).isValid)
    }
}

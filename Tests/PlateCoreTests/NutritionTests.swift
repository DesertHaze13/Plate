import XCTest
@testable import PlateCore
final class NutritionTests: XCTestCase {
    func testRecompositionIsAModestDeficitAndMacrosBalance() {
        var profile = Profile(); profile.calorieCap = 10000
        let breakdown = NutritionCalculator.breakdown(for: profile)
        XCTAssertEqual(breakdown.bmr, 1698.75, accuracy: 0.001)
        XCTAssertEqual(breakdown.maintenance, 2633.0625, accuracy: 0.001)
        let targets = NutritionCalculator.targets(for: profile).nutrients
        XCTAssertEqual(targets.calories, 2633.0625 * 0.9, accuracy: 0.001)
        XCTAssertEqual(targets.protein, 150)
        XCTAssertEqual(targets.protein*4 + targets.carbs*4 + targets.fat*9, targets.calories, accuracy: 0.001)
    }
    func testGoalAdjustmentsAreRelativeToMaintenance() {
        var p = Profile(); p.calorieCap = 10000; let maintenance = NutritionCalculator.breakdown(for: p).maintenance
        p.goal = .leanBulk; XCTAssertEqual(NutritionCalculator.targets(for: p).nutrients.calories, maintenance*1.1, accuracy: 0.001)
        p.goal = .cut; XCTAssertEqual(NutritionCalculator.targets(for: p).nutrients.calories, maintenance*0.8, accuracy: 0.001)
    }
    func testCalorieCapIsNeverExceeded() {
        var p = Profile(); p.calorieCap = 2200
        let breakdown = NutritionCalculator.breakdown(for: p)
        XCTAssertTrue(breakdown.capped)
        let targets = NutritionCalculator.targets(for: p).nutrients
        XCTAssertEqual(targets.calories, 2200, accuracy: 0.001)
        XCTAssertEqual(targets.protein*4 + targets.carbs*4 + targets.fat*9, 2200, accuracy: 0.001)
        p.goal = .cut; XCTAssertFalse(NutritionCalculator.breakdown(for: p).capped)
    }
    func testMeasuredActivityReplacesMultiplier() {
        var p = Profile(); p.measuredActiveKcal = 450
        XCTAssertEqual(NutritionCalculator.breakdown(for: p).maintenance, 1698.75 + 450, accuracy: 0.001)
    }
    func testCappingTrimsCarbsBeforeProtein() {
        let t = Targets(nutrients: .init(calories: 2600, protein: 160, carbs: 300, fat: 80)).capped(at: 2200)
        XCTAssertEqual(t.nutrients.calories, 2200); XCTAssertEqual(t.nutrients.protein, 160); XCTAssertEqual(t.nutrients.carbs, 200, accuracy: 0.001)
        XCTAssertEqual(t.nutrients.fat, 80)
    }
    func testOldMealsWithoutCaffeineStillDecode() throws {
        let json = #"{"calories":100,"protein":1,"carbs":2,"fat":3,"fiber":0,"sugar":0}"#
        let n = try JSONDecoder().decode(Nutrients.self, from: Data(json.utf8))
        XCTAssertEqual(n.calories, 100); XCTAssertEqual(n.caffeine, 0)
    }
    func testCaffeineEstimates() {
        XCTAssertEqual(CaffeineEstimate.perServing(name: "Iced Kopi Susu"), 95)
        XCTAssertEqual(CaffeineEstimate.perServing(name: "Decaf latte"), 3)
        XCTAssertEqual(CaffeineEstimate.perServing(name: "Matcha latte"), 70)
        XCTAssertNil(CaffeineEstimate.perServing(name: "Steak"))
        XCTAssertTrue(CaffeineEstimate.isCoffee("Flat white")); XCTAssertFalse(CaffeineEstimate.isCoffee("Green tea"))
        let item = FoodItem(name: "Espresso", category: .drinks, servingDescription: "1 shot", nutrients: .init(calories: 2), quantity: 2)
        XCTAssertEqual(CaffeineEstimate.milligrams(for: item), 128)
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
    func testDefaultAndLegacyCeilingApplyAcrossAllGoals() {
        for goal in [Goal.cut, .recomp, .leanBulk] {
            var profile = Profile(); profile.goal = goal; profile.weightKG = 100; profile.activityMultiplier = 1.9
            XCTAssertLessThanOrEqual(NutritionCalculator.targets(for: profile).nutrients.calories, 2200)
            profile.calorieCap = nil
            XCTAssertEqual(profile.dailyCalorieCeiling, 2200)
            XCTAssertLessThanOrEqual(NutritionCalculator.targets(for: profile).nutrients.calories, 2200)
        }
    }

    func testReviewedCorrectionPreservesOtherFoodsAndAddsMissedFood() {
        let rice = FoodItem(name: "Rice", category: .carbs, servingDescription: "100 g", nutrients: .init(calories: 130))
        let fish = FoodItem(name: "Fish", category: .protein, servingDescription: "100 g", nutrients: .init(calories: 150))
        let chicken = FoodItem(name: "Chicken", category: .protein, servingDescription: "120 g", nutrients: .init(calories: 198))
        let corrected = FoodReview.applying([chicken], replacing: fish.id, to: [rice, fish])
        XCTAssertEqual(corrected, [rice, chicken])
        XCTAssertEqual(FoodReview.applying([fish], replacing: nil, to: corrected), [rice, chicken, fish])
        XCTAssertEqual(FoodReview.applying([], replacing: rice.id, to: corrected), corrected)
        XCTAssertEqual(FoodReview.applying([fish], replacing: "removed-item", to: corrected), corrected)
    }

    func testOveragesDistinguishCaloriesAndEachMacro() {
        let target = Nutrients(calories: 2200, protein: 120, carbs: 250, fat: 70)
        let eaten = Nutrients(calories: 2000, protein: 140, carbs: 260, fat: 80)
        let warnings = NutritionOverage.evaluate(eaten: eaten, target: target)
        XCTAssertEqual(warnings.map(\.id), ["protein", "carbs", "fat"])
        XCTAssertEqual(warnings.map(\.excess), [20, 10, 10])
        XCTAssertTrue(NutritionOverage.evaluate(eaten: target, target: target).isEmpty)
        XCTAssertEqual(NutritionOverage.evaluate(eaten: .init(calories: 2201), target: target).first?.id, "calories")
        XCTAssertTrue(NutritionOverage.evaluate(eaten: eaten, target: .zero).isEmpty)
    }

}

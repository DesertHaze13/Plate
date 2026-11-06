import XCTest
@testable import PlateCore
final class GuidanceTests: XCTestCase {
    let target = Targets(nutrients: .init(calories: 2400, protein: 160, carbs: 260, fat: 70))
    func testCalmAndThreshold() {
        XCTAssertEqual(DailyGuidance(eaten: .init(calories: 2039), target: target).state, .calm)
        XCTAssertEqual(DailyGuidance(eaten: .init(calories: 2040), target: target).state, .almost)
    }
    func testToleranceHasPriorityAtBothEdges() {
        XCTAssertEqual(DailyGuidance(eaten: .init(calories: 2350), target: target).state, .hit)
        XCTAssertEqual(DailyGuidance(eaten: .init(calories: 2450), target: target).state, .hit)
        XCTAssertEqual(DailyGuidance(eaten: .init(calories: 2451), target: target).state, .over)
    }
    func testProteinNudgeAndNoCompensatoryTarget() {
        let guidance = DailyGuidance(eaten: .init(calories: 2100, protein: 100), target: target)
        XCTAssertEqual(guidance.remaining, 300); XCTAssertEqual(guidance.proteinRemaining, 60)
        XCTAssertTrue(guidance.message.contains("lean protein"))
        XCTAssertTrue(DailyGuidance(eaten: .init(calories: 2800), target: target).message.contains("stays the same"))
    }
    func testTrainingDatesRemainCompatibleWithExistingSettings() throws {
        let old = Data("{\"metric\":true,\"summaryEnabled\":false,\"summaryHour\":21}".utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertNil(settings.trainingDayKeys)
        settings.trainingDayKeys = ["2026-11-06"]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.trainingDayKeys, ["2026-11-06"])
    }
    func testFemaleFormula() {
        var p = Profile(); p.male = false; p.age = 30; p.weightKG = 60; p.heightCM = 165; p.activityMultiplier = 1.2
        XCTAssertEqual(NutritionCalculator.targets(for: p).nutrients.calories, (600+1031.25-150-161)*1.2, accuracy: 0.001)
    }
    func testEachMacroHasIndependentFullAndOverWarnings() {
        let checks = TargetProgress.all(eaten: .init(calories: 1000, protein: 160, carbs: 100, fat: 78), targets: target)
        XCTAssertEqual(checks.map(\.nutrient), [.calories, .protein, .carbs, .fat])
        XCTAssertEqual(checks.map(\.state), [.under, .met, .under, .over])
        XCTAssertEqual(checks.last?.excess, 8)
        XCTAssertEqual(checks[2].remaining, 160)
    }
    func testWarningStartsAtConfiguredThresholdAndTracksExactMacroTarget() {
        let below = TargetProgress(nutrient: .protein, amount: 135.99, target: 160)
        XCTAssertEqual(below.state, .under)
        XCTAssertEqual(TargetProgress(nutrient: .protein, amount: 136, target: 160).state, .near)
        XCTAssertEqual(TargetProgress(nutrient: .protein, amount: 159.9, target: 160).state, .near)
        XCTAssertEqual(TargetProgress(nutrient: .protein, amount: 160, target: 160).state, .met)
        XCTAssertEqual(TargetProgress(nutrient: .protein, amount: 160.1, target: 160).state, .over)
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: 56, target: 70, warningFraction: 0.8).state, .near)
    }
    func testCalorieToleranceDoesNotHideMacroExcess() {
        let checks = TargetProgress.all(eaten: .init(calories: 2450, protein: 160.1, carbs: 260, fat: 70), targets: target)
        XCTAssertEqual(checks[0].state, .met)
        XCTAssertEqual(checks[1].state, .over)
        XCTAssertEqual(TargetProgress.all(eaten: .init(calories: 2450.1), targets: target)[0].state, .over)
    }
    func testZeroAndInvalidTargetsDoNotShowFalseFullWarnings() {
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: 0, target: 0).state, .unset)
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: 10, target: .nan).state, .unset)
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: .infinity, target: 70).state, .unset)
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: 60, target: 70, warningFraction: .nan).state, .near)
    }
    func testProjectedMealCrossesFatTargetWithoutChangingExistingTotals() {
        let existing = Nutrients(calories: 1500, protein: 100, carbs: 150, fat: 60)
        let meal = Nutrients(calories: 350, protein: 20, carbs: 30, fat: 18)
        let checks = TargetProgress.all(eaten: existing + meal, targets: target)
        XCTAssertEqual(checks[3].state, .over)
        XCTAssertEqual(checks[3].excess, 8)
        XCTAssertEqual(existing.fat, 60)
        XCTAssertEqual(target.nutrients.fat, 70)
    }

    func testPieMacroSharesUseEnergyAndPreserveGrams() {
        let slices = PieBreakdown.macros(.init(calories: 400, protein: 20, carbs: 60, fat: 8))
        XCTAssertEqual(slices.map(\.calories), [80, 240, 72])
        XCTAssertEqual(slices.map(\.grams), [20, 60, 8])
        XCTAssertEqual(slices.reduce(0) { $0 + $1.calories }, 392)
    }
    func testPieSelectionUsesCumulativeEnergyAndExactBoundaries() {
        let slices = PieBreakdown.macros(.init(protein: 20, carbs: 60, fat: 8))
        XCTAssertEqual(PieBreakdown.slice(at: 0, in: slices)?.nutrient, .protein)
        XCTAssertEqual(PieBreakdown.slice(at: 79.9, in: slices)?.nutrient, .protein)
        XCTAssertEqual(PieBreakdown.slice(at: 80, in: slices)?.nutrient, .carbs)
        XCTAssertEqual(PieBreakdown.slice(at: 320, in: slices)?.nutrient, .fat)
        XCTAssertEqual(PieBreakdown.slice(at: 392, in: slices)?.nutrient, .fat)
        XCTAssertNil(PieBreakdown.slice(at: 393, in: slices))
        XCTAssertNil(PieBreakdown.slice(at: -1, in: slices))
    }
    func testPieSkipsZeroAndInvalidSectorsWithoutFabricatingEnergy() {
        XCTAssertNil(PieBreakdown.slice(at: 0, in: PieBreakdown.macros(.zero)))
        let slices = PieBreakdown.macros(.init(protein: .nan, carbs: 1, fat: 0))
        XCTAssertEqual(PieBreakdown.slice(at: 0, in: slices)?.nutrient, .carbs)
        XCTAssertNil(PieBreakdown.slice(at: .nan, in: slices))
        XCTAssertEqual(slices.reduce(0) { $0 + $1.calories }, 4)
    }
    func testFoodCategoryPieCountsPortionsAndDoesNotCountMacrosTwice() {
        let rice = FoodItem(name: "Rice", category: .carbs, servingDescription: "bowl", nutrients: .init(calories: 200, carbs: 40), quantity: 2)
        let fish = FoodItem(name: "Fish", category: .protein, servingDescription: "portion", nutrients: .init(calories: 150, protein: 25))
        let meals = [Meal(items: [rice, fish])]
        let slices = PieBreakdown.foodCategories(meals)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices.first { $0.category == .carbs }?.calories, 400)
        XCTAssertEqual(slices.first { $0.category == .protein }?.calories, 150)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.calories }, 550)
        XCTAssertTrue(slices.allSatisfy { $0.grams == nil && $0.nutrient == nil })
    }

}

import XCTest
@testable import PlateCore
final class RecognitionUpgradeTests: XCTestCase {
    func testLegacyLiteAndEmptySettingsUpgradeToFullFlash() {
        XCTAssertEqual(RecognitionModel.modelName(configured: "gemini-3.5-flash"), RecognitionModel.advanced)
        XCTAssertEqual(RecognitionModel.modelName(configured: nil), RecognitionModel.advanced)
        XCTAssertEqual(RecognitionModel.modelName(configured: "  "), RecognitionModel.advanced)
        XCTAssertEqual(RecognitionModel.modelName(configured: "gemini-3.5-flash-lite"), RecognitionModel.advanced)
        XCTAssertEqual(RecognitionModel.modelName(configured: " custom-model "), "custom-model")
    }
    func testIndonesianWarningReportsExcessAndRemaining() {
        let excess = TargetProgress(nutrient: .fat, amount: 100.9, target: 60)
        XCTAssertEqual(excess.state, .over)
        XCTAssertEqual(excess.nutrient.indonesianTitle, "Lemak")
        XCTAssertEqual(excess.indonesianDifference, "Lebih 40,9 g")
        XCTAssertEqual(TargetProgress(nutrient: .carbs, amount: 100, target: 200).indonesianDifference, "Sisa 100 g")
        XCTAssertEqual(TargetProgress(nutrient: .protein, amount: 100, target: 100).indonesianDifference, "Target tercapai")
    }
    func testIndonesianWarningNeverRoundsTinyExcessToZero() {
        XCTAssertEqual(TargetProgress(nutrient: .fat, amount: 60.01, target: 60).indonesianDifference, "Lebih kurang dari 0,1 g")
    }
    func testHistoricalDayTotalsUseJakartaBoundaryAndServingQuantity() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let beforeMidnight = ISO8601DateFormatter().date(from: "2026-11-05T16:59:00Z")!
        let afterMidnight = ISO8601DateFormatter().date(from: "2026-11-05T17:01:00Z")!
        let food = FoodItem(name: "Tempe", category: .protein, servingDescription: "100 g", nutrients: .init(calories: 200, protein: 20), quantity: 1.5)
        let records = [Meal(timestamp: beforeMidnight, items: [food], calendar: calendar), Meal(timestamp: afterMidnight, items: [food], calendar: calendar)]
        XCTAssertEqual(HistoryMath.totals(records, on: beforeMidnight, calendar: calendar).calories, 300)
        XCTAssertEqual(HistoryMath.totals(records, on: afterMidnight, calendar: calendar).protein, 30)
        XCTAssertEqual(records.count, 2)
    }
    func testSelectedDateResolvesItsTrainingTargetWithoutChangingToday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let date = ISO8601DateFormatter().date(from: "2026-11-05T17:01:00Z")!
        let rest = Targets(nutrients: .init(calories: 2000))
        var training = rest; training.nutrients.calories = 2400
        let key = DayKey.make(date, calendar: calendar)
        XCTAssertEqual(HistoryMath.targets(on: date, rest: rest, training: training, trainingDayKeys: [key], calendar: calendar).nutrients.calories, 2400)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)!
        XCTAssertEqual(HistoryMath.targets(on: yesterday, rest: rest, training: training, trainingDayKeys: [key], calendar: calendar).nutrients.calories, 2000)
        XCTAssertEqual(HistoryMath.targets(on: date, rest: rest, training: nil, trainingDayKeys: [key], calendar: calendar).nutrients.calories, 2000)
    }

    func testAIRevisionPreservesFoodIdentityAndDoesNotTouchSiblings() throws {
        let original = FoodItem(name: "Perkedel", category: .carbs, servingDescription: "1 buah", nutrients: .init(calories: 150), quantity: 2)
        let sibling = FoodItem(name: "Nasi", category: .carbs, servingDescription: "100 g", nutrients: .init(calories: 130))
        let proposal = FoodItem(name: "Kroket daging", category: .snacks, servingDescription: "1 buah kecil", nutrients: .init(calories: 170, protein: 5, carbs: 18, fat: 9), quantity: 2, source: .cloud)
        var meal = Meal(items: [original, sibling]); let timestamp = meal.timestamp; let mealID = meal.id
        meal.items[0] = FoodAIRevision.applying(proposal, to: original)
        XCTAssertEqual(meal.items[0].id, original.id)
        XCTAssertEqual(meal.items[0].name, "Kroket daging")
        XCTAssertEqual(meal.items[0].total.calories, 340)
        XCTAssertEqual(meal.items[1], sibling)
        XCTAssertEqual(meal.id, mealID); XCTAssertEqual(meal.timestamp, timestamp)
        XCTAssertEqual(try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meal)), meal)
    }

    func testFallbackIsOptionalAndNeverHandlesVerificationFailures() {
        XCTAssertEqual(RecognitionModel.candidates(primary: RecognitionModel.advanced, allowFallback: false), [RecognitionModel.advanced])
        XCTAssertEqual(RecognitionModel.candidates(primary: RecognitionModel.advanced, allowFallback: true), [RecognitionModel.advanced, RecognitionModel.fallback])
        XCTAssertTrue(RecognitionModel.allowsFallback(statusCode: 429))
        XCTAssertTrue(RecognitionModel.allowsFallback(statusCode: 503))
        XCTAssertFalse(RecognitionModel.allowsFallback(statusCode: 403))
        XCTAssertFalse(RecognitionModel.allowsFallback(statusCode: 400))
    }
    func testLegacyFoodWithoutAIModelStillDecodes() throws {
        var food = FoodItem(name: "Tempe", category: .protein, servingDescription: "100 g", nutrients: .init(calories: 200))
        food.aiModel = RecognitionModel.fallback
        let encoded = try JSONEncoder().encode(food)
        XCTAssertEqual(try JSONDecoder().decode(FoodItem.self, from: encoded).aiModel, RecognitionModel.fallback)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]); legacy.removeValue(forKey: "aiModel")
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.aiModel); XCTAssertEqual(restored.id, food.id); XCTAssertEqual(restored.nutrients, food.nutrients)
    }

}

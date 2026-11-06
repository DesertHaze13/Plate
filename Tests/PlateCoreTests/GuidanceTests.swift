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
}

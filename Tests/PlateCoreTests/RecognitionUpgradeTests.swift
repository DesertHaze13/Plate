import XCTest
@testable import PlateCore
final class RecognitionUpgradeTests: XCTestCase {
    func testLegacyLiteAndEmptySettingsUpgradeToFullFlash() {
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
}

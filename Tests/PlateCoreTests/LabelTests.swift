import XCTest
@testable import PlateCore
final class LabelTests: XCTestCase {
    func testEnglishPerServing() throws {
        let result = try XCTUnwrap(LabelParser.parse("Nutrition Facts\nServing size 30 g\nServings per container 4\nCalories 120\nProtein 6 g\nTotal carbohydrate 15 g\nTotal fat 4 g\nDietary fiber 2 g\nSugars 3 g"))
        XCTAssertEqual(result.items[0].nutrients.calories, 120)
        XCTAssertEqual(result.items[0].nutrients.protein, 6)
        XCTAssertEqual(result.label?.servingGrams, 30)
        XCTAssertEqual(result.label?.wholePackageQuantity, 4)
        XCTAssertEqual(result.items[0].needsReviewFields, [])
    }
    func testIndonesianPer100G() throws {
        let result = try XCTUnwrap(LabelParser.parse("Informasi Nilai Gizi\nTakaran Saji 30 g\nJumlah Sajian per Kemasan 5\nPer 100 g\nEnergi Total 400 kkal\nProtein 20 g\nKarbohidrat Total 60 g\nLemak Total 8 g\nSerat Pangan 4 g\nGula 5,5 g"))
        XCTAssertEqual(result.label?.basis, .per100Grams)
        XCTAssertEqual(result.items[0].quantity, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.items[0].total.calories, 120, accuracy: 0.0001)
        XCTAssertEqual(result.items[0].nutrients.sugar, 5.5)
        XCTAssertEqual(result.label!.wholePackageQuantity!, 1.5, accuracy: 0.0001)
    }
    func testKilojoulesAndHalfServing() throws {
        let result = try XCTUnwrap(LabelParser.parse("Energy 418.4 kJ\nProtein 5 g\nCarbs 10 g\nFat 4 g"))
        XCTAssertEqual(result.items[0].nutrients.calories, 100, accuracy: 0.0001)
        XCTAssertEqual(result.items[0].nutrients.scaled(by: result.label!.quantity(servings: 0.5)).calories, 50, accuracy: 0.0001)
    }
    func testKcalWinsWhenBothUnitsArePrinted() throws {
        let result = try XCTUnwrap(LabelParser.parse("Energy 840 kJ / 200 kcal\nProtein 10 g\nCarbs 20 g\nFat 8 g"))
        XCTAssertEqual(result.items[0].nutrients.calories, 200)
    }
    func testPerPackageServingMath() throws {
        let result = try XCTUnwrap(LabelParser.parse("Per package\nServings per container 2\nCalories 400\nProtein 20 g\nCarbs 40 g\nFat 12 g"))
        XCTAssertEqual(result.label?.basis, .package)
        XCTAssertEqual(result.items[0].total.calories, 200)
        XCTAssertEqual(result.label?.wholePackageQuantity, 1)
    }
    func testMissingNumberIsFlaggedRatherThanInvented() throws {
        let result = try XCTUnwrap(LabelParser.parse("Calories 120\nProtein unreadable\nCarbs 20 g\nFat 4 g"))
        XCTAssertEqual(result.items[0].needsReviewFields, ["protein"])
    }
    func testMenuCaloriesAreDetectedAsNutritionText() {
        XCTAssertTrue(LabelParser.looksLikeNutrition("Grilled chicken 400 kcal\nRice bowl 650 kcal"))
    }
    func testValueBeforeNameMealBoxLabel() throws {
        // Printed on a takeaway box: amount first, plural names, "Cal" for kcal.
        let result = try XCTUnwrap(LabelParser.parse("EASY\nPEASY\nCLASSIC CAESAR\nCHICKEN SALAD\n328 Cal\n15.5 g Carbs\n25 g Proteins\n17.4 g Fats"))
        let item = result.items[0]
        XCTAssertEqual(item.nutrients.calories, 328)
        XCTAssertEqual(item.nutrients.carbs, 15.5)
        XCTAssertEqual(item.nutrients.protein, 25)
        XCTAssertEqual(item.nutrients.fat, 17.4)
        XCTAssertEqual(item.needsReviewFields, [])
        XCTAssertEqual(item.name, "Classic Caesar Chicken Salad")
        XCTAssertEqual(item.quantity, 1)
    }
    func testValueNeverComesFromTheNextRow() throws {
        // Old bug: "Carbs" picked up the 25 printed on the protein row below it.
        let result = try XCTUnwrap(LabelParser.parse("Calories 300\nCarbs\n25 g Proteins\nFat 10 g"))
        XCTAssertEqual(result.items[0].nutrients.protein, 25)
        XCTAssertEqual(result.items[0].needsReviewFields, ["carbs"])
    }
    func testMergedValueFirstRows() throws {
        let result = try XCTUnwrap(LabelParser.parse("328 Cal 15.5 g Carbs\n25 g Proteins 17.4 g Fats"))
        XCTAssertEqual(result.items[0].nutrients.protein, 25)
        XCTAssertEqual(result.items[0].nutrients.fat, 17.4)
    }
    func testCaloriesFromFatIsNotTotalFat() throws {
        let result = try XCTUnwrap(LabelParser.parse("Calories 200 Calories from Fat 110\nTotal Fat 12g\nProtein 9 g\nTotal Carbohydrate 30g"))
        XCTAssertEqual(result.items[0].nutrients.calories, 200)
        XCTAssertEqual(result.items[0].nutrients.fat, 12)
    }
    func testNonNutritionTextDoesNotBecomeMeal() { XCTAssertNil(LabelParser.parse("Welcome to the restaurant. Have a lovely day.")) }
}

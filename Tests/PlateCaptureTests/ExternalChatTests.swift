import XCTest
@testable import PlateLocal
import PlateCore
final class ExternalChatTests: XCTestCase {
    private func answer(_ id: UUID, calories: String = "250", count: Int = 1) -> String {
        let food = "{\"name\":\"Tempe goreng\",\"category\":\"protein\",\"serving\":\"100 g dimakan\",\"calories\":\(calories),\"protein\":12,\"carbs\":8,\"fat\":15,\"fiber\":null,\"sugar\":null,\"confidence\":0.6,\"source\":\"estimated\",\"bounds\":null}"
        return "{\"requestID\":\"\(id.uuidString)\",\"kind\":\"food\",\"items\":[" + Array(repeating: food, count: count).joined(separator: ",") + "]}"
    }
    func testFencedAnswerMatchesOnlyCurrentRequest() throws {
        let id = UUID()
        XCTAssertEqual(try ExternalFoodChat.decode("```json\n" + answer(id) + "\n```", expectedID: id, correcting: false).items.count, 1)
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(id), expectedID: UUID(), correcting: false))
    }
    func testInvalidAndMultipleCorrectionsRejected() {
        let id = UUID()
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(id, calories: "-4"), expectedID: id, correcting: false))
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(id, count: 2), expectedID: id, correcting: true))
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(id, count: 0), expectedID: id, correcting: false))
    }
    func testImportKeepsOriginalIDAndFlagsUnknownNutrition() throws {
        let id = UUID(), original = FoodItem(name: "Tempe", category: .protein, servingDescription: "1 potong", nutrients: .zero)
        let result = try RecognitionService().importChatResult(answer(id, calories: "null"), requestID: id, original: original)
        XCTAssertEqual(result.first?.id, original.id)
        XCTAssertEqual(result.first?.quantity, 1)
        XCTAssertTrue(result.first?.needsReviewFields?.contains("calories") == true)
    }
    func testUsersActualJamuReplyCanBeReviewedAfterReopeningForm() throws {
        let reply = #"{"requestID":"F1361B90-F852-4874-A8CA-E781E9BB7934","kind":"food","items":[{"name":"Jamu beras kencur (manis, dengan es)","category":"drinks","serving":"1 gelas kecil, perkiraan ±200 ml","calories":110,"protein":1,"carbs":26,"fat":0.3,"fiber":0.3,"sugar":20,"confidence":0.6,"source":"estimated","bounds":null}]}"#
        let currentID = UUID()
        XCTAssertThrowsError(try ExternalFoodChat.decode(reply, expectedID: currentID, correcting: false))
        let foods = try RecognitionService().importChatResult(reply, requestID: currentID, original: nil, allowDifferentRequest: true)
        XCTAssertEqual(foods.first?.total.calories, 110)
        XCTAssertEqual(foods.first?.category, .drinks)
        XCTAssertEqual(foods.first?.quantity, 1)
    }
    func testReviewOtherPromptStillValidatesNutritionAndSingleFoodEdit() {
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(UUID(), calories: "-2"), expectedID: UUID(), correcting: false, allowDifferentRequest: true))
        XCTAssertThrowsError(try ExternalFoodChat.decode(answer(UUID(), count: 2), expectedID: UUID(), correcting: true, allowDifferentRequest: true))
    }
}

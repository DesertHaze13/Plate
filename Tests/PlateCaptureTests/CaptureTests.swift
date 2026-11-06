import XCTest
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import PlateLocal
import PlateCore

final class CaptureTests: XCTestCase {
    func testGoogleLoginRequiresMatchingCallbackBeforeCallingSDK() {
        let client = "123-example.apps.googleusercontent.com"
        XCTAssertNil(GoogleLoginConfiguration.validationError(clientID: client, callbackSchemes: ["plate", "com.googleusercontent.apps.123-example"]))
        XCTAssertNotNil(GoogleLoginConfiguration.validationError(clientID: client, callbackSchemes: ["plate", "com.googleusercontent.apps.other-project"]))
        XCTAssertNotNil(GoogleLoginConfiguration.validationError(clientID: client, callbackSchemes: []))
        XCTAssertNotNil(GoogleLoginConfiguration.validationError(clientID: "", callbackSchemes: []))
        XCTAssertNotNil(GoogleLoginConfiguration.validationError(clientID: "invalid", callbackSchemes: []))
    }
    @MainActor func testRealVisionOCRAndServingPipeline() async throws {
        let lines = ["Nutrition Facts", "Serving size 30 g", "Servings per container 4", "Per 100 g", "Energy 1673.6 kJ", "Protein 20 g", "Total Carbohydrates 60 g", "Total Fat 8 g", "Dietary Fiber 4 g", "Sugars 5 g"]
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
        let font = CTFontCreateWithName("Helvetica" as CFString, 46, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 65, y: 1100-Double(index)*90)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let png = bytes as Data
        let encoded = try ImageCodec.prepare(png)
        let analysis = try await RecognitionService().analyze(data: encoded.full, cloudAllowed: false)
        XCTAssertEqual(analysis.kind, .label)
        let food = try XCTUnwrap(analysis.items.first)
        XCTAssertEqual(food.source, .label)
        XCTAssertEqual(food.nutrients.calories, 400, accuracy: 0.1)
        XCTAssertEqual(food.nutrients.protein, 20, accuracy: 0.1)
        XCTAssertEqual(food.quantity, 0.3, accuracy: 0.001)
        XCTAssertEqual(food.total.calories, 120, accuracy: 0.1)
        XCTAssertLessThanOrEqual(encoded.full.count, 750*1024)
    }
    func testInvalidImageFailsWithoutCloud() async {
        do { _ = try await RecognitionService().analyze(data: Data([0, 1, 2]), cloudAllowed: false); XCTFail("Malformed image should fail") }
        catch { /* Expected: no guessed nutrition and no cloud fallback. */ }
    }
    @MainActor func testPhotoQueueDoesNotEvictPendingOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhotoStore(root: root)
        let photo = EncodedPhoto(full: Data(repeating: 1, count: 12 * 1024 * 1024), thumbnail: Data([2]))
        try store.stage(photo, mealID: "first")
        XCTAssertThrowsError(try store.stage(photo, mealID: "second"))
        XCTAssertEqual(store.read("first.jpg"), photo.full)
        XCTAssertNil(store.read("second.jpg"))
        try store.save(Data([3]), key: "remote-old-copy")
        store.clearDownloadedCache()
        XCTAssertNil(store.read("remote-old-copy"))
        XCTAssertEqual(store.read("first.jpg"), photo.full)
        store.removePending(mealID: "first")
        XCTAssertNil(store.read("first.jpg"))
        XCTAssertNil(store.read("first-thumb.jpg"))
        XCTAssertThrowsError(try store.stage(photo, mealID: "../outside"))
    }
    func testExclusionMasksUseTopLeftCoordinates() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let masked = try ImageCodec.masking(bytes as Data, regions: [.init(x: 0, y: 0, width: 0.5, height: 0.5)])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(masked as CFData, nil))
        let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        func pixel(_ x: Int, _ y: Int) throws -> UInt8 {
            let crop = try XCTUnwrap(result.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            let sample = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            sample.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return try XCTUnwrap(sample.data).load(as: UInt8.self)
        }
        XCTAssertLessThan(try pixel(25, 25), 10)
        XCTAssertGreaterThan(try pixel(25, 75), 240)
        XCTAssertGreaterThan(try pixel(75, 25), 240)
        XCTAssertEqual(try ImageCodec.masking(bytes as Data, regions: []), bytes as Data)
    }

    func testDescriptionRejectsUnreadableReferencePhotoBeforeAI() async {
        do {
            _ = try await RecognitionService().describe("Grilled chicken, 120 g", photo: Data([0, 1, 2]), correcting: nil, cloudAllowed: false)
            XCTFail("An attached reference photo must be decoded before estimating")
        } catch RecognitionError.unreadable { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

}

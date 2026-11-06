import XCTest
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import PlateLocal
import PlateCore

final class CaptureTests: XCTestCase {
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
}

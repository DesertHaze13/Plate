import Foundation
import ImageIO
import UniformTypeIdentifiers

struct EncodedPhoto: Sendable { let full: Data; let thumbnail: Data }
enum ImageCodec {
    static func prepare(_ data: Data) throws -> EncodedPhoto {
        var full = try jpeg(data, maxPixels: 1600, quality: 0.76)
        for size in [1400, 1200, 1000, 800] where full.count > 750 * 1024 { full = try jpeg(data, maxPixels: size, quality: 0.7) }
        return .init(full: full, thumbnail: try jpeg(data, maxPixels: 320, quality: 0.65))
    }
    private static func jpeg(_ data: Data, maxPixels: Int, quality: Double) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw RecognitionError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw RecognitionError.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecognitionError.unreadable }
        return output as Data
    }
}
@MainActor final class PhotoStore {
    static let shared = PhotoStore()
    private let root = URL.applicationSupportDirectory.appending(path: "Plate/Photos", directoryHint: .isDirectory)
    func save(_ data: Data, key: String) throws {
        guard !key.contains("/"), !key.contains("..") else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: key), options: .atomic)
    }
    func read(_ key: String) -> Data? {
        guard !key.contains("/"), !key.contains("..") else { return nil }
        return try? Data(contentsOf: root.appending(path: key))
    }
    func load(path: String, sync: FirebaseSync) async -> Data? {
        let key = "remote-" + path.replacingOccurrences(of: "/", with: "_")
        if let local = read(path) ?? read(key) { return local }
        do { let data = try await sync.photoData(path: path); try save(data, key: key); return data }
        catch { return nil }
    }
}

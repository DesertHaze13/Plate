import Foundation
import ImageIO
import UniformTypeIdentifiers
import PlateCore

struct EncodedPhoto: Sendable { let full: Data; let thumbnail: Data }
enum ImageCodec {
    static func prepare(_ data: Data) throws -> EncodedPhoto {
        var full = try jpeg(data, maxPixels: 1600, quality: 0.76)
        for size in [1400, 1200, 1000, 800] where full.count > 750 * 1024 { full = try jpeg(data, maxPixels: size, quality: 0.7) }
        return .init(full: full, thumbnail: try jpeg(data, maxPixels: 320, quality: 0.65))
    }
    /// Opaque masks remove excluded pixels before either OCR or an AI model sees them.
    static func masking(_ data: Data, regions: [FoodBounds]) throws -> Data {
        guard !regions.isEmpty else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RecognitionError.unreadable }
        let width = Double(image.width), height = Double(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for r in regions {
            guard [r.x, r.y, r.width, r.height].allSatisfy({ $0.isFinite }), r.width > 0, r.height > 0 else { continue }
            let rect = CGRect(x: r.x * width, y: (1 - r.y - r.height) * height, width: r.width * width, height: r.height * height)
            context.fill(rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)))
        }
        guard let masked = context.makeImage() else { throw RecognitionError.unreadable }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw RecognitionError.unreadable }
        CGImageDestinationAddImage(destination, masked, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecognitionError.unreadable }
        return bytes as Data
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
    static let pendingLimit = 20 * 1024 * 1024
    private let root: URL
    private var reclaiming = false
    private let memory = NSCache<NSString, NSData>()
    init(root: URL = URL.applicationSupportDirectory.appending(path: "Plate/Photos", directoryHint: .isDirectory)) {
        self.root = root
        memory.totalCostLimit = 12 * 1024 * 1024
        clearDownloadedCache()
    }
    private func valid(_ key: String) -> Bool { !key.isEmpty && !key.contains("/") && !key.contains("..") }
    func save(_ data: Data, key: String) throws {
        guard valid(key) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: key), options: .atomic)
        var url = root.appending(path: key)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
    func stage(_ photo: EncodedPhoto, mealID: String) throws {
        guard valid(mealID) else { throw CocoaError(.fileWriteInvalidFileName) }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let used = files.filter { !$0.lastPathComponent.hasPrefix("remote-") }.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard used + photo.full.count + photo.thumbnail.count <= Self.pendingLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        do {
            try save(photo.full, key: "\(mealID).jpg")
            try save(photo.thumbnail, key: "\(mealID)-thumb.jpg")
        } catch { removePending(mealID: mealID); throw error }
    }
    func read(_ key: String) -> Data? {
        guard valid(key) else { return nil }
        return try? Data(contentsOf: root.appending(path: key))
    }
    func removePending(mealID: String) {
        for key in ["\(mealID).jpg", "\(mealID)-thumb.jpg"] where valid(key) { try? FileManager.default.removeItem(at: root.appending(path: key)) }
    }
    func removeLegacyCopies(paths: [String]) {
        for path in paths {
            let key = "remote-" + path.replacingOccurrences(of: "/", with: "_")
            if valid(key) { try? FileManager.default.removeItem(at: root.appending(path: key)) }
            memory.removeObject(forKey: path as NSString)
        }
    }
    func clearDownloadedCache() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("remote-") { try? FileManager.default.removeItem(at: file) }
    }
    /// Upgrade existing installations without deleting their only copy of a photo.
    func reclaimUploadedCopies(meals: [Meal], sync: FirebaseSync) async {
        guard !reclaiming, let uid = sync.userID else { return }
        reclaiming = true; defer { reclaiming = false }
        for meal in meals {
            guard sync.userID == uid else { break }
            guard read("\(meal.id).jpg") != nil,
                  let full = meal.photoPath, let thumb = meal.thumbnailPath,
                  full.hasPrefix("users/\(uid)/") || full.hasPrefix("firestore://users/\(uid)/") else { continue }
            do {
                _ = try await sync.photoData(path: full)
                _ = try await sync.photoData(path: thumb)
                guard sync.userID == uid else { break }
                PhotoOutbox.shared.remove(mealID: meal.id)
                removeLegacyCopies(paths: [full, thumb])
            } catch { continue } // Offline and failed uploads must keep their originals.
        }
    }
    func load(path: String, sync: FirebaseSync) async -> Data? {
        if !path.contains("/") { return read(path) } // Existing meals stored only on this device.
        guard let uid = sync.userID, path.hasPrefix("users/\(uid)/") || path.hasPrefix("firestore://users/\(uid)/") else { return nil }
        if let cached = memory.object(forKey: path as NSString) { return cached as Data }
        let parts = path.split(separator: "/").map(String.init)
        let key: String?
        if path.hasPrefix("firestore://"), let id = parts.last { key = id + ".jpg" }
        else if parts.count >= 2 { key = parts[parts.count - 2] + (parts.last == "thumbnail.jpg" ? "-thumb.jpg" : ".jpg") }
        else { key = nil }
        if let key, let pending = read(key) { return pending }
        do {
            let data = try await sync.photoData(path: path)
            memory.setObject(data as NSData, forKey: path as NSString, cost: data.count)
            return data
        } catch { return nil }
    }
}

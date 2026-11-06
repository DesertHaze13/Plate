import Foundation
import Network
import Observation

@MainActor final class PhotoOutbox {
    static let shared = PhotoOutbox()
    struct Pending: Codable, Equatable { var uid: String; var mealID: String }
    private var pending: [Pending] = []
    private var flushing = false
    private let file = URL.applicationSupportDirectory.appending(path: "Plate/photo-outbox.json")
    private init() { if let data = try? Data(contentsOf: file) { pending = (try? JSONDecoder().decode([Pending].self, from: data)) ?? [] } }
    func enqueue(uid: String, mealID: String) throws {
        let value = Pending(uid: uid, mealID: mealID)
        if !pending.contains(value) { pending.append(value) }
        try persist()
    }
    func remove(mealID: String) { pending.removeAll { $0.mealID == mealID }; try? persist() }
    func flush(sync: FirebaseSync) async {
        guard !flushing, let uid = sync.userID else { return }; flushing = true; defer { flushing = false }
        for row in pending.filter({ $0.uid == uid }) {
            guard sync.userID == uid else { break }
            guard let photo = PhotoStore.shared.read("\(row.mealID).jpg"), let thumbnail = PhotoStore.shared.read("\(row.mealID)-thumb.jpg") else { continue }
            do {
                _ = try await sync.uploadPhoto(mealID: row.mealID, jpeg: photo, thumbnail: thumbnail)
                pending.removeAll { $0 == row }; try persist()
            } catch { break } // Persisted work retries when the app reconnects or becomes active.
        }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: file, options: .atomic)
    }
}
@MainActor @Observable final class Connectivity {
    var online = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.online = online }
        }
        monitor.start(queue: DispatchQueue(label: "Plate.Connectivity"))
    }
}

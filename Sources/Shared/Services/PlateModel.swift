import SwiftUI
import Observation
import PlateCore

@MainActor @Observable final class PlateModel {
    let store: MealStore
    let sync: FirebaseSync
    let recognition = RecognitionService()
    let health = HealthService()
    let connectivity = Connectivity()
    var showCapture = false
    var showOnboarding = false
    var importedPhoto: Data?
    var notice: String?
    init() {
        let store = MealStore(); self.store = store; self.sync = FirebaseSync(store: store)
    }
    func finishOnboarding(profile: Profile, targets: Targets) {
        store.account.profile = profile; store.account.targets = targets; store.account.onboarded = true
        sync.saveAccount(); showOnboarding = false
    }
    func saveMeal(_ meal: Meal, photo: EncodedPhoto? = nil, saveToLibrary: Bool = false, barcode: String? = nil) async {
        var meal = meal
        if let photo {
            do {
                let key = "\(meal.id).jpg", thumb = "\(meal.id)-thumb.jpg"
                try PhotoStore.shared.save(photo.full, key: key); try PhotoStore.shared.save(photo.thumbnail, key: thumb)
                meal.photoPath = key; meal.thumbnailPath = thumb
                if let uid = sync.userID, let paths = sync.photoPaths(mealID: meal.id) {
                    meal.photoPath = paths.0; meal.thumbnailPath = paths.1
                    try PhotoStore.shared.save(photo.full, key: "remote-" + meal.photoPath!.replacingOccurrences(of: "/", with: "_"))
                    try PhotoStore.shared.save(photo.thumbnail, key: "remote-" + meal.thumbnailPath!.replacingOccurrences(of: "/", with: "_"))
                    try PhotoOutbox.shared.enqueue(uid: uid, mealID: meal.id)
                }
            } catch { notice = "Could not save the photo: \(error.localizedDescription)" }
        }
        sync.save(meal)
        Task { await PhotoOutbox.shared.flush(sync: sync) }
        if saveToLibrary { for item in meal.items { store.saveFood(item, barcode: barcode) }; sync.saveAccount() }
        if UserDefaults.standard.bool(forKey: "healthEnabled") {
            do { try await health.write(meal) } catch { notice = "Meal saved. Health could not be updated: \(error.localizedDescription)" }
        }
        await SummaryNotifications.schedule(store: store)
    }
    func repeatMeal(_ past: Meal) {
        Task {
            var photo: EncodedPhoto?
            if let path = past.photoPath, let data = await PhotoStore.shared.load(path: path, sync: sync) { photo = try? ImageCodec.prepare(data) }
            await saveMeal(Meal(items: past.items, source: past.source), photo: photo)
        }
    }
    func logFood(_ food: SavedFood) { sync.save(Meal(items: [food.item], source: food.item.source)) }
    func handleURL(_ url: URL) {
        if sync.handleURL(url) { return }
        if url.scheme == "plate", url.host == "capture" { showCapture = true }
    }
}

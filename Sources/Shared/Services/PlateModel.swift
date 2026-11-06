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
    /// Latest body data, workouts and burn from Apple Health. Empty until Health is connected.
    var healthProfile: HealthProfile?
    var workoutsToday: [HealthWorkout] = []
    var energyDays: [EnergyDay] = []
    @ObservationIgnored private var refreshingHealth = false
    var healthEnabled: Bool { UserDefaults.standard.bool(forKey: "healthEnabled") }
    init() {
        let store = MealStore(); self.store = store; self.sync = FirebaseSync(store: store)
    }
    func finishOnboarding(profile: Profile, targets: Targets) {
        store.account.profile = profile; store.targets = targets; store.account.onboarded = true
        sync.saveAccount(); showOnboarding = false
    }
    func saveMeal(_ meal: Meal, photo: EncodedPhoto? = nil, saveToLibrary: Bool = false, barcode: String? = nil) async {
        var meal = meal
        if let photo {
            if let uid = sync.userID, let paths = sync.photoPaths(mealID: meal.id) {
                do {
                    try PhotoStore.shared.stage(photo, mealID: meal.id)
                    try PhotoOutbox.shared.enqueue(uid: uid, mealID: meal.id)
                    meal.photoPath = paths.0; meal.thumbnailPath = paths.1
                } catch {
                    PhotoStore.shared.removePending(mealID: meal.id)
                    notice = "Meal saved without a photo. The temporary upload queue is full or unavailable. Connect and let uploads finish before saving more photos."
                }
            } else {
                notice = "Meal saved without a photo. Sign in to save meal photos in Firebase without keeping them on this device."
            }
        }
        sync.save(meal)
        Task { await PhotoOutbox.shared.flush(sync: sync) }
        if saveToLibrary { for item in meal.items { store.saveFood(item, barcode: barcode) }; sync.saveAccount() }
        await writeToHealth(meal)
        await SummaryNotifications.schedule(store: store)
    }
    /// Saves an edited meal and replaces its copy in Apple Health.
    func updateMeal(_ meal: Meal) {
        guard meal.isValid else { notice = "Check portions and nutrition before saving the meal."; return }
        var meal = meal; meal.updatedAt = .now
        sync.save(meal)
        Task { await writeToHealth(meal) }
    }
    func deleteMeal(_ meal: Meal) {
        sync.remove(meal)
        if healthEnabled { Task { await health.delete(mealID: meal.id) } }
    }
    private func writeToHealth(_ meal: Meal) async {
        guard healthEnabled else { return }
        do { try await health.write(meal) } catch { notice = "Meal saved. Health could not be updated: \(error.localizedDescription)" }
    }
    /// Turns on Apple Health and pulls in everything Plate can use.
    func connectHealth() async throws {
        try await health.authorize()
        UserDefaults.standard.set(true, forKey: "healthEnabled")
        await refreshHealth()
    }
    /// Reads body data, weights, workouts and burn from Apple Health and fills them into the profile.
    func refreshHealth() async {
        guard healthEnabled, !refreshingHealth else { return }
        refreshingHealth = true; defer { refreshingHealth = false }
        let body = await health.profile()
        healthProfile = body
        apply(body)
        if let weights = try? await health.weights() {
            let known = Set(store.account.weights.map(\.id))
            let new = weights.filter { !known.contains($0.id) }
            if !new.isEmpty { store.account.weights.append(contentsOf: new); sync.saveAccount() }
        }
        if store.account.profile.measuredActiveKcal != nil, let average = await health.averageActiveEnergy() {
            var profile = store.account.profile; profile.measuredActiveKcal = average.rounded()
            updateProfile(profile)
        }
        workoutsToday = await health.workouts()
        energyDays = await health.energyDays(30).filter { $0.burned > 0 }
    }
    private func apply(_ body: HealthProfile) { updateProfile(Self.merge(body, into: store.account.profile)) }
    /// The profile with any plausible Health values filled in.
    static func merge(_ body: HealthProfile, into profile: Profile) -> Profile {
        var profile = profile
        if let age = body.age, (18...100).contains(age) { profile.age = age }
        if let male = body.male { profile.male = male }
        if let height = body.heightCM, (100...250).contains(height) { profile.heightCM = (height * 10).rounded() / 10 }
        if let weight = body.weightKG, (30...350).contains(weight) { profile.weightKG = (weight * 10).rounded() / 10 }
        return profile
    }
    /// Saves a new profile. Targets follow automatically unless they were typed in by hand.
    func updateProfile(_ profile: Profile) {
        let old = store.account.profile
        guard profile != old else { return }
        let previous = NutritionCalculator.targets(for: old).nutrients
        let current = store.account.targets
        let followsProfile = abs(current.nutrients.calories - previous.calories) < 1 && abs(current.nutrients.protein - previous.protein) < 1
        store.account.profile = profile
        if followsProfile {
            var targets = NutritionCalculator.targets(for: profile)
            targets.warningFraction = current.warningFraction; targets.tolerance = current.tolerance
            store.targets = targets
        }
        sync.saveAccount()
    }
    func repeatMeal(_ past: Meal) {
        Task {
            var photo: EncodedPhoto?
            if let path = past.photoPath, let data = await PhotoStore.shared.load(path: path, sync: sync) { photo = try? ImageCodec.prepare(data) }
            await saveMeal(Meal(items: past.items, source: past.source), photo: photo)
        }
    }
    func logFood(_ food: SavedFood) {
        let meal = Meal(items: [food.item], source: food.item.source)
        sync.save(meal)
        Task { await writeToHealth(meal) }
    }
    func handleURL(_ url: URL) {
        if sync.handleURL(url) { return }
        if url.scheme == "plate", url.host == "capture" { showCapture = true }
    }
}

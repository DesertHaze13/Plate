#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore
import PlateCore

/// Account-scoped typed documents. Auth rules enforce the same boundary remotely.
@MainActor struct UserDocuments {
    let uid: String
    private var root: DocumentReference { Firestore.firestore().collection("users").document(uid) }
    func saveProfile(_ profile: Profile) throws { try set(profile, collection: "profile", id: "current") }
    func saveGoals(_ goals: Targets) throws { try set(goals, collection: "goals", id: "current") }
    func saveSettings(_ settings: AppSettings) throws { try set(settings, collection: "settings", id: "current") }
    func saveFood(_ food: SavedFood) throws { try set(food, collection: "myFoods", id: food.id) }
    func saveWeight(_ weight: WeightEntry) throws { try set(weight, collection: "weights", id: weight.id) }
    func profile() async throws -> Profile? {
        let snapshot = try await root.collection("profile").document("current").getDocument()
        return snapshot.exists ? try snapshot.data(as: Profile.self) : nil
    }
    private func set<T: Encodable>(_ value: T, collection: String, id: String) throws {
        var data = try Firestore.Encoder().encode(value)
        data["updatedAt"] = FieldValue.serverTimestamp()
        root.collection(collection).document(id).setData(data)
    }
}

#endif

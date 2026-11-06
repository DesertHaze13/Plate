#if canImport(FirebaseCore)
import Foundation
import Observation
import CryptoKit
@preconcurrency import GoogleSignIn
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseStorage
import FirebaseAppCheck
import PlateCore

@MainActor @Observable final class FirebaseSync {
    private(set) var status = "On this device"
    private(set) var userID: String?
    private(set) var error: String?
    let configured: Bool
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var mealListener: ListenerRegistration?
    private var accountListeners: [ListenerRegistration] = []
    private(set) var signingIn = false
    private let store: MealStore
    private static var firestoreConfigured = false
    init(store: MealStore) {
        self.store = store
        configured = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        guard configured else { return }
        if FirebaseApp.app() == nil {
            AppCheck.setAppCheckProviderFactory(PlateAppCheckFactory())
            FirebaseApp.configure()
        }
        if let app = FirebaseApp.app() { PlateAppCheckFactory.prepareEnrollment(app: app) }
        // Firestore throws (crashing the app) if settings change after it has started,
        // so apply them only once per process, however many times this is constructed.
        if !Self.firestoreConfigured {
            Self.firestoreConfigured = true
            let db = Firestore.firestore()
            let settings = db.settings
            settings.cacheSettings = PersistentCacheSettings()
            db.settings = settings
        }
        status = "Sign in to sync"
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor [weak self] in self?.observe(uid: uid) }
        }
    }
    private func observe(uid: String?) {
        mealListener?.remove(); mealListener = nil
        accountListeners.forEach { $0.remove() }; accountListeners = []
        userID = uid; store.load(account: uid)
        guard let uid else { status = "Sign in to sync"; return }
        status = "Connecting…"
        observeAccount(uid: uid)
        mealListener = Firestore.firestore().collection("users").document(uid).collection("meals")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                if let error { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message; self?.status = "Sync needs attention" }; return }
                guard let snapshot else { return }
                do {
                    let meals = try snapshot.documents.map { try $0.data(as: Meal.self, with: .estimate) }
                    let status = snapshot.metadata.hasPendingWrites ? "Waiting to upload" : snapshot.metadata.isFromCache ? "Offline · cached meals" : "Up to date"
                    Task { @MainActor [weak self] in
                        guard let self, self.userID == uid else { return }
                        self.store.replaceFromCloud(meals); self.status = status; self.error = nil
                    }
                } catch { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = "A meal could not be read: \(message)" } }
            }
    }
    private func observeAccount(uid: String) {
        let root = Firestore.firestore().collection("users").document(uid)
        func observe<T: Decodable & Sendable>(_ collection: String, as type: T.Type, apply: @escaping @MainActor (MealStore, [T]) -> Void) {
            let listener = root.collection(collection).addSnapshotListener { [weak self] snapshot, error in
                if let error { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message }; return }
                guard let snapshot else { return }
                do {
                    let values = try snapshot.documents.map { try $0.data(as: T.self, with: .estimate) }
                    Task { @MainActor [weak self] in
                        guard let self, self.userID == uid else { return }
                        apply(self.store, values); self.store.persistAccount()
                    }
                } catch { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message } }
            }
            accountListeners.append(listener)
        }
        observe("profile", as: Profile.self) { store, values in if let first = values.first { store.account.profile = first; store.account.onboarded = true } }
        observe("goals", as: Targets.self) { store, values in if let first = values.first { store.account.targets = first } }
        observe("settings", as: AppSettings.self) { store, values in if let first = values.first { store.account.settings = first } }
        observe("myFoods", as: SavedFood.self) { $0.account.foods = $1 }
        observe("weights", as: WeightEntry.self) { $0.account.weights = $1.sorted { $0.timestamp < $1.timestamp } }
    }
    func saveAccount() {
        store.persistAccount()
        guard let uid = userID else { return }
        let root = Firestore.firestore().collection("users").document(uid)
        var writes: [(DocumentReference, [String: Any])] = []
        do {
            func put<T: Encodable>(_ value: T, _ collection: String, _ id: String = "current") throws {
                var data = try Firestore.Encoder().encode(value); data["updatedAt"] = FieldValue.serverTimestamp()
                writes.append((root.collection(collection).document(id), data))
            }
            try put(store.account.profile, "profile"); try put(store.account.targets, "goals"); try put(store.account.settings, "settings")
            for food in store.account.foods { try put(food, "myFoods", food.id) }
            for weight in store.account.weights { try put(weight, "weights", weight.id) }
            for start in stride(from: 0, to: writes.count, by: 400) {
                let batch = Firestore.firestore().batch()
                for (reference, data) in writes[start..<min(start+400, writes.count)] { batch.setData(data, forDocument: reference) }
                batch.commit { [weak self] error in if let error { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message } } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func photoPaths(mealID: String) -> (String, String)? {
        guard let uid = userID else { return nil }
        if UserDefaults.standard.bool(forKey: "useFirebaseStorage") { return ("users/\(uid)/meals/\(mealID)/photo.jpg", "users/\(uid)/meals/\(mealID)/thumbnail.jpg") }
        return ("firestore://users/\(uid)/photos/\(mealID)", "firestore://users/\(uid)/photos/\(mealID)-thumb")
    }
    func photoData(path: String) async throws -> Data {
        if path.hasPrefix("firestore://") {
            let document = try await Firestore.firestore().document(String(path.dropFirst("firestore://".count))).getDocument()
            guard let bytes = document.data()?["bytes"] as? Data else { throw CocoaError(.fileNoSuchFile) }
            return bytes
        }
        return try await Storage.storage().reference(withPath: path).data(maxSize: 10 * 1024 * 1024)
    }
    func save(_ meal: Meal) {
        guard meal.isValid else { error = "Check the nutrition values before saving."; return }
        guard let uid = userID else { store.save(meal); return }
        do {
            var data = try Firestore.Encoder().encode(meal)
            data["updatedAt"] = FieldValue.serverTimestamp()
            Firestore.firestore().collection("users").document(uid).collection("meals").document(meal.id).setData(data) { [weak self] error in
                if let error { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ meal: Meal) {
        PhotoOutbox.shared.remove(mealID: meal.id)
        guard let uid = userID else { store.remove(meal.id); return }
        let root = Firestore.firestore().collection("users").document(uid)
        let batch = Firestore.firestore().batch()
        batch.deleteDocument(root.collection("meals").document(meal.id))
        if meal.photoPath?.hasPrefix("firestore://") == true {
            batch.deleteDocument(root.collection("photos").document(meal.id)); batch.deleteDocument(root.collection("photos").document(meal.id + "-thumb"))
        }
        batch.commit { [weak self] error in if let error { let message = error.localizedDescription; Task { @MainActor [weak self] in self?.error = message } } }
    }

    func signInWithGoogle() async {
        guard configured, let clientID = FirebaseApp.app()?.options.clientID else { error = "Google sign-in configuration is missing. Download the updated Firebase configuration after enabling Google."; return }
        signingIn = true; defer { signingIn = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            #if os(iOS)
            guard var presenter = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { throw CocoaError(.featureUnsupported) }
            while let next = presenter.presentedViewController { presenter = next }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            #else
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { throw CocoaError(.featureUnsupported) }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            #endif
            guard let token = result.user.idToken?.tokenString else { throw CocoaError(.coderValueNotFound) }
            let credential = GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func handleURL(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
    func signOut() { do { try Auth.auth().signOut(); GIDSignIn.sharedInstance.signOut() } catch { self.error = error.localizedDescription } }
    /// Caller supplies compressed JPEG and thumbnail; stage two provides image processing.
    func uploadPhoto(mealID: String, jpeg: Data, thumbnail: Data) async throws -> (String, String) {
        guard let uid = userID else { throw CocoaError(.userCancelled) }
        try await Firestore.firestore().waitForPendingWrites()
        let document = try await Firestore.firestore().collection("users").document(uid).collection("meals").document(mealID).getDocument(source: .server)
        guard document.exists else { return ("", "") }
        if !UserDefaults.standard.bool(forKey: "useFirebaseStorage") {
            guard jpeg.count <= 750 * 1024, thumbnail.count <= 100 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            let root = Firestore.firestore().collection("users").document(uid).collection("photos")
            let batch = Firestore.firestore().batch()
            batch.setData(["bytes": jpeg, "contentType": "image/jpeg", "updatedAt": FieldValue.serverTimestamp()], forDocument: root.document(mealID))
            batch.setData(["bytes": thumbnail, "contentType": "image/jpeg", "updatedAt": FieldValue.serverTimestamp()], forDocument: root.document(mealID + "-thumb"))
            try await batch.commit()
            return ("firestore://users/\(uid)/photos/\(mealID)", "firestore://users/\(uid)/photos/\(mealID)-thumb")
        }
        let root = Storage.storage().reference().child("users/\(uid)/meals/\(mealID)")
        let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
        _ = try await root.child("photo.jpg").putDataAsync(jpeg, metadata: metadata)
        _ = try await root.child("thumbnail.jpg").putDataAsync(thumbnail, metadata: metadata)
        return (root.child("photo.jpg").fullPath, root.child("thumbnail.jpg").fullPath)
    }
}

#else
import Foundation
import Observation

import PlateCore
@MainActor @Observable final class FirebaseSync {
    let configured = false
    let status = "On this device"
    let userID: String? = nil
    var error: String?
    private let store: MealStore
    init(store: MealStore) { self.store = store }
    func save(_ meal: Meal) { store.save(meal) }
    func remove(_ meal: Meal) {
        PhotoOutbox.shared.remove(mealID: meal.id); store.remove(meal.id) }
    let signingIn = false
    func signInWithGoogle() async {}
    func handleURL(_ url: URL) -> Bool { false }
    func signOut() {}
    func saveAccount() { store.persistAccount() }
    func photoPaths(mealID: String) -> (String, String)? { nil }
    func photoData(path: String) async throws -> Data { throw CocoaError(.fileNoSuchFile) }
    func uploadPhoto(mealID: String, jpeg: Data, thumbnail: Data) async throws -> (String, String) { throw CocoaError(.fileWriteNoPermission) }
}
#endif

#if canImport(FirebaseAppCheck)
import Foundation
import FirebaseCore
import FirebaseAppCheck
/// Personal-team builds use revocable App Check debug attestations.
final class PlateAppCheckFactory: NSObject, AppCheckProviderFactory {
    @MainActor static func prepareEnrollment(app: FirebaseApp) {
        guard let provider = AppCheckDebugProvider(app: app) else { return }
        let file = URL.applicationSupportDirectory.appending(path: "Plate/attestation.json")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["token": provider.currentDebugToken(), "appID": app.options.googleAppID])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var url = file; try url.setResourceValues(values)
        } catch { /* App Check still works; installer reports enrollment-file failures. */ }
    }
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? { AppCheckDebugProvider(app: app) }
}
#endif

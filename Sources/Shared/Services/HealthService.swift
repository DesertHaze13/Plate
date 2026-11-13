import Foundation
import CryptoKit
import PlateCore
#if os(iOS)
@preconcurrency import HealthKit
#endif

/// Body data read from Apple Health. A nil field was missing or not permitted.
struct HealthProfile: Equatable, Sendable {
    var age: Int?
    var male: Bool?
    var heightCM: Double?
    var weightKG: Double?
    var systolic: Double?
    var diastolic: Double?
    var bloodPressureDate: Date?
    var restingHeartRate: Double?
    var isEmpty: Bool { age == nil && male == nil && heightCM == nil && weightKG == nil && systolic == nil && restingHeartRate == nil }
}
struct HealthWorkout: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let duration: TimeInterval
    let kcal: Double
}
/// One day of energy burned, as Apple Health recorded it.
struct EnergyDay: Identifiable, Equatable, Sendable {
    let date: Date
    var basal: Double
    var active: Double
    var id: Date { date }
    var burned: Double { basal + active }
}

/// Tracks HealthKit versions across retries and restarts without storing nutrition values.
struct HealthExportLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let fingerprint: String
        let version: Int
        var completed: Bool
    }
    private(set) var entries: [String: Entry] = [:]

    mutating func prepare(mealID: String, fingerprint: String, now: Date) -> Entry {
        if let entry = entries[mealID], entry.fingerprint == fingerprint { return entry }
        let previous = entries[mealID]?.version ?? 0
        let version = max(previous + 1, Int(now.timeIntervalSince1970 * 1000))
        let entry = Entry(fingerprint: fingerprint, version: version, completed: false)
        entries[mealID] = entry
        return entry
    }

    mutating func complete(mealID: String, fingerprint: String) {
        guard entries[mealID]?.fingerprint == fingerprint else { return }
        entries[mealID]?.completed = true
    }

    mutating func forget(mealID: String) { entries.removeValue(forKey: mealID) }
}

enum HealthNutritionError: LocalizedError {
    case permissionDenied
    var errorDescription: String? {
        "Allow Plate to write Dietary Energy in Apple Health, then enable the other nutrition types you want to sync."
    }
}

@MainActor final class HealthService {
    #if os(iOS)
    private let store = HKHealthStore()
    private let mealKey = "PlateMealID"
    private let nutrients: [(HKQuantityTypeIdentifier, KeyPath<Nutrients, Double>, HKUnit)] = [
        (.dietaryEnergyConsumed, \.calories, .kilocalorie()), (.dietaryProtein, \.protein, .gram()),
        (.dietaryCarbohydrates, \.carbs, .gram()), (.dietaryFatTotal, \.fat, .gram()),
        (.dietaryFiber, \.fiber, .gram()), (.dietarySugar, \.sugar, .gram()),
        (.dietaryCaffeine, \.caffeine, .gramUnit(with: .milli))
    ]
    private var authorized = false
    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        let write = Set(nutrients.map { HKQuantityType($0.0) as HKSampleType })
        let readIdentifiers: [HKQuantityTypeIdentifier] = [.bodyMass, .height, .bloodPressureSystolic, .bloodPressureDiastolic, .restingHeartRate, .activeEnergyBurned, .basalEnergyBurned]
        var read = Set(readIdentifiers.map { HKQuantityType($0) as HKObjectType })
        read.insert(HKObjectType.workoutType())
        read.insert(HKCharacteristicType(.dateOfBirth)); read.insert(HKCharacteristicType(.biologicalSex))
        try await store.requestAuthorization(toShare: write, read: read)
        authorized = true
    }
    private func ensureAuthorized() async { if !authorized { try? await authorize() } }

    // MARK: Food → Health

    private let revisionKey = "PlateNutritionRevision"
    private let ledgerKey = "plateHealthExportLedgerV1"
    private let deletionKey = "plateHealthPendingDeletionsV1"
    private var completedThisSession: [String: String] = [:]
    private var ledger: HealthExportLedger = {
        guard let data = UserDefaults.standard.data(forKey: "plateHealthExportLedgerV1"),
              let value = try? JSONDecoder().decode(HealthExportLedger.self, from: data) else { return HealthExportLedger() }
        return value
    }()

    var canWriteNutrition: Bool {
        HKHealthStore.isHealthDataAvailable() &&
            store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized
    }

    var unsharedNutritionNames: [String] {
        let names = ["Calories", "Protein", "Carbohydrates", "Fat", "Fiber", "Sugar", "Caffeine"]
        return zip(nutrients, names).compactMap { nutrient, name in
            store.authorizationStatus(for: HKQuantityType(nutrient.0)) == .sharingAuthorized ? nil : name
        }
    }

    func refreshNutritionCache() { completedThisSession = [:] }

    private struct FoodExport: Encodable {
        let id: String
        let name: String
        let amounts: [Double]
    }
    private struct MealExport: Encodable {
        let timestamp: Date
        let type: String
        let identifiers: [String]
        let foods: [FoodExport]
    }

    /// Saves stable, versioned food records. A retry replaces the same samples.
    /// The new records are saved before older records are removed.
    func write(_ meal: Meal) async throws {
        guard canWriteNutrition else { throw HealthNutritionError.permissionDenied }
        guard meal.isValid, let foodType = HKCorrelationType.correlationType(forIdentifier: .food) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let writable = nutrients.filter { store.authorizationStatus(for: HKQuantityType($0.0)) == .sharingAuthorized }
        let export = MealExport(timestamp: meal.timestamp, type: meal.type.rawValue,
                                identifiers: writable.map { $0.0.rawValue },
                                foods: meal.items.map { item in
                                    FoodExport(id: item.id, name: item.name, amounts: writable.map { item.total[keyPath: $0.1] })
                                })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = Data(SHA256.hash(data: try encoder.encode(export))).base64EncodedString()
        guard completedThisSession[meal.id] != fingerprint else { return }
        let entry = ledger.prepare(mealID: meal.id, fingerprint: fingerprint, now: .now)
        if !entry.completed { try persistLedger() }

        let foods = export.foods.map { item in
            let identifier = "plate-food-\(meal.id)-\(item.id)"
            let metadata: [String: Any] = [
                HKMetadataKeyFoodType: item.name,
                mealKey: meal.id,
                "PlateMeal": meal.type.rawValue,
                revisionKey: fingerprint,
                HKMetadataKeySyncIdentifier: identifier,
                HKMetadataKeySyncVersion: entry.version
            ]
            let samples: [HKSample] = zip(writable, item.amounts).map { nutrient, amount in
                let (type, _, unit) = nutrient
                var sampleMetadata = metadata
                sampleMetadata[HKMetadataKeySyncIdentifier] = identifier + "-" + type.rawValue
                return HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: amount),
                                        start: meal.timestamp, end: meal.timestamp, metadata: sampleMetadata)
            }
            var foodMetadata = metadata
            if CaffeineEstimate.isCoffee(item.name) { foodMetadata["PlateDrink"] = "coffee" }
            return HKCorrelation(type: foodType, start: meal.timestamp, end: meal.timestamp,
                                 objects: Set(samples), metadata: foodMetadata)
        }
        try await store.save(foods)
        try await removeNutrition(mealID: meal.id, keeping: fingerprint)
        if !entry.completed {
            ledger.complete(mealID: meal.id, fingerprint: fingerprint)
            try persistLedger()
        }
        completedThisSession[meal.id] = fingerprint
    }

    /// Persisted before a meal is removed so Health deletion can be retried after relaunch.
    func queueDeletion(mealID: String) {
        var pending = UserDefaults.standard.stringArray(forKey: deletionKey) ?? []
        if !pending.contains(mealID) { pending.append(mealID) }
        UserDefaults.standard.set(pending, forKey: deletionKey)
    }

    func flushDeletions() async throws {
        for id in UserDefaults.standard.stringArray(forKey: deletionKey) ?? [] {
            try await removeNutrition(mealID: id, keeping: nil)
            ledger.forget(mealID: id)
            try persistLedger()
            completedThisSession.removeValue(forKey: id)
            let pending = UserDefaults.standard.stringArray(forKey: deletionKey) ?? []
            UserDefaults.standard.set(pending.filter { $0 != id }, forKey: deletionKey)
        }
    }

    private func persistLedger() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(ledger), forKey: ledgerKey)
    }

    private func removeNutrition(mealID: String, keeping revision: String?) async throws {
        let current = HKQuery.predicateForObjects(withMetadataKey: mealKey, allowedValues: [mealID])
        let obsolete: NSPredicate
        if let revision {
            let keep = HKQuery.predicateForObjects(withMetadataKey: revisionKey, allowedValues: [revision])
            obsolete = NSCompoundPredicate(andPredicateWithSubpredicates: [
                current, NSCompoundPredicate(notPredicateWithSubpredicate: keep)
            ])
        } else { obsolete = current }
        if let food = HKCorrelationType.correlationType(forIdentifier: .food) {
            _ = try await store.deleteObjects(of: food, predicate: obsolete)
        }
        for (identifier, _, _) in nutrients {
            let type = HKQuantityType(identifier)
            let legacy = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                     allowedValues: ["plate-\(mealID)-\(identifier.rawValue)"])
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [obsolete, legacy])
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    // MARK: Health → Plate

    func profile() async -> HealthProfile {
        await ensureAuthorized()
        var result = HealthProfile()
        if let components = try? store.dateOfBirthComponents(), let birth = Calendar.current.date(from: components) {
            result.age = Calendar.current.dateComponents([.year], from: birth, to: .now).year
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            if sex == .male { result.male = true } else if sex == .female { result.male = false }
        }
        result.heightCM = await latest(.height, unit: .meterUnit(with: .centi))?.value
        result.weightKG = await latest(.bodyMass, unit: .gramUnit(with: .kilo))?.value
        if let pressure = await bloodPressure() {
            result.systolic = pressure.systolic; result.diastolic = pressure.diastolic; result.bloodPressureDate = pressure.date
        }
        result.restingHeartRate = await latest(.restingHeartRate, unit: .count().unitDivided(by: .minute()))?.value
        return result
    }
    private func bloodPressure() async -> (systolic: Double, diastolic: Double, date: Date)? {
        guard let type = HKCorrelationType.correlationType(forIdentifier: .bloodPressure) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                guard let reading = samples?.first as? HKCorrelation,
                      let systolic = reading.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample,
                      let diastolic = reading.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: (systolic.quantity.doubleValue(for: .millimeterOfMercury()), diastolic.quantity.doubleValue(for: .millimeterOfMercury()), reading.startDate))
            }
            store.execute(query)
        }
    }
    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, date: Date)? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(identifier), predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample { continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.startDate)) }
                else { continuation.resume(returning: nil) }
            }
            store.execute(query)
        }
    }
    func weights() async throws -> [WeightEntry] {
        await ensureAuthorized()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil, limit: 365, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKQuantitySample] ?? []).map { sample in
                    var entry = WeightEntry(timestamp: sample.startDate, kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))); entry.id = "health-" + sample.uuid.uuidString; return entry
                }
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }
    func workouts(on day: Date = .now) async -> [HealthWorkout] {
        await ensureAuthorized()
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let list = (samples as? [HKWorkout] ?? []).map { workout in
                    let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    let info = HealthService.describe(workout.workoutActivityType)
                    return HealthWorkout(id: workout.uuid, name: info.name, symbol: info.symbol, start: workout.startDate, duration: workout.duration, kcal: kcal)
                }
                continuation.resume(returning: list)
            }
            store.execute(query)
        }
    }
    /// Resting and active energy for each of the last `count` days, oldest first. Today is still in progress.
    func energyDays(_ count: Int) async -> [EnergyDay] {
        await ensureAuthorized()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard count > 0, let start = calendar.date(byAdding: .day, value: -(count-1), to: today) else { return [] }
        let basal = await dailySums(.basalEnergyBurned, from: start)
        let active = await dailySums(.activeEnergyBurned, from: start)
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DayKey.make(day)
            return EnergyDay(date: day, basal: basal[key] ?? 0, active: active[key] ?? 0)
        }
    }
    /// Average active energy over the last 14 complete days that have data. Nil with fewer than 3 such days.
    func averageActiveEnergy() async -> Double? {
        let days = await energyDays(15).dropLast().filter { $0.active > 0 }
        guard days.count >= 3 else { return nil }
        return days.reduce(0) { $0 + $1.active } / Double(days.count)
    }
    func activeEnergyToday() async throws -> Double { (await energyDays(1)).first?.active ?? 0 }
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, from start: Date) async -> [String: Double] {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(identifier), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: nil), options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var sums: [String: Double] = [:]
                for statistics in collection?.statistics() ?? [] {
                    if let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) { sums[DayKey.make(statistics.startDate)] = value }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }
    nonisolated private static func describe(_ type: HKWorkoutActivityType) -> (name: String, symbol: String) {
        switch type {
        case .running: ("Run", "figure.run")
        case .walking: ("Walk", "figure.walk")
        case .cycling: ("Ride", "figure.outdoor.cycle")
        case .traditionalStrengthTraining, .functionalStrengthTraining: ("Strength", "dumbbell.fill")
        case .highIntensityIntervalTraining: ("HIIT", "figure.highintensity.intervaltraining")
        case .swimming: ("Swim", "figure.pool.swim")
        case .yoga: ("Yoga", "figure.yoga")
        case .hiking: ("Hike", "figure.hiking")
        case .coreTraining: ("Core", "figure.core.training")
        case .elliptical: ("Elliptical", "figure.elliptical")
        case .rowing: ("Row", "figure.rower")
        case .soccer: ("Football", "figure.soccer")
        case .badminton: ("Badminton", "figure.badminton")
        case .basketball: ("Basketball", "figure.basketball")
        case .pilates: ("Pilates", "figure.pilates")
        case .cardioDance, .socialDance: ("Dance", "figure.dance")
        default: ("Workout", "figure.mixed.cardio")
        }
    }
    #else
    func authorize() async throws { throw CocoaError(.featureUnsupported) }
    var canWriteNutrition: Bool { false }
    var unsharedNutritionNames: [String] { [] }
    func refreshNutritionCache() {}
    func write(_ meal: Meal) async throws {}
    func queueDeletion(mealID: String) {}
    func flushDeletions() async throws {}
    func profile() async -> HealthProfile { HealthProfile() }
    func weights() async throws -> [WeightEntry] { [] }
    func workouts(on day: Date = .now) async -> [HealthWorkout] { [] }
    func energyDays(_ count: Int) async -> [EnergyDay] { [] }
    func averageActiveEnergy() async -> Double? { nil }
    func activeEnergyToday() async throws -> Double { 0 }
    #endif
}

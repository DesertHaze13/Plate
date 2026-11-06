import Foundation
import PlateCore
#if os(iOS)
@preconcurrency import HealthKit
#endif

@MainActor final class HealthService {
    #if os(iOS)
    private let store = HKHealthStore()
    private let nutrients: [(HKQuantityTypeIdentifier, KeyPath<Nutrients, Double>, HKUnit)] = [
        (.dietaryEnergyConsumed, \.calories, .kilocalorie()), (.dietaryProtein, \.protein, .gram()),
        (.dietaryCarbohydrates, \.carbs, .gram()), (.dietaryFatTotal, \.fat, .gram()),
        (.dietaryFiber, \.fiber, .gram()), (.dietarySugar, \.sugar, .gram())
    ]
    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        let write = Set(nutrients.compactMap { HKQuantityType.quantityType(forIdentifier: $0.0) })
        let read = Set([HKQuantityType.quantityType(forIdentifier: .bodyMass)!, HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!])
        try await store.requestAuthorization(toShare: write, read: read)
    }
    func write(_ meal: Meal) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let samples = nutrients.compactMap { identifier, key, unit -> HKQuantitySample? in
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: meal.total[keyPath: key]), start: meal.timestamp, end: meal.timestamp, metadata: [HKMetadataKeySyncIdentifier: "plate-\(meal.id)-\(identifier.rawValue)", HKMetadataKeySyncVersion: Int(meal.updatedAt.timeIntervalSince1970)])
        }
        try await store.save(samples)
    }
    func weights() async throws -> [WeightEntry] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 365, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let entries = (samples as? [HKQuantitySample] ?? []).map { sample in
                    var entry = WeightEntry(timestamp: sample.startDate, kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))); entry.id = "health-" + sample.uuid.uuidString; return entry
                }
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }
    func activeEnergyToday() async throws -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0) }
            })
        }
    }
    #else
    func authorize() async throws { throw CocoaError(.featureUnsupported) }
    func write(_ meal: Meal) async throws {}
    func weights() async throws -> [WeightEntry] { [] }
    func activeEnergyToday() async throws -> Double { 0 }
    #endif
}

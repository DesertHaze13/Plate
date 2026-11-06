import Foundation
public struct SharedSnapshot: Codable, Sendable {
    public static let appGroup = "group.com.dony.plate"
    public var dayKey: String
    public var eaten: Nutrients
    public var targets: Nutrients
    public var updatedAt: Date
    public init(dayKey: String, eaten: Nutrients, targets: Nutrients, updatedAt: Date = .now) { self.dayKey = dayKey; self.eaten = eaten; self.targets = targets; self.updatedAt = updatedAt }
    public static func read() -> Self? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "todaySnapshot"), let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        if snapshot.dayKey == DayKey.make(.now) { return snapshot }
        return Self(dayKey: DayKey.make(.now), eaten: .zero, targets: snapshot.targets)
    }
}

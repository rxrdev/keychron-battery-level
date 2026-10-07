import Foundation

extension Notification.Name {
    /// Posted on the main queue with a `BatteryReading` as the object.
    public static let didUpdateBatteryReading = Notification.Name("didUpdateBatteryReading")
}

/// One battery report from any source. A `nil` level means disconnected or unknown.
/// `isWired` marks a device on a USB cable, which reports no battery level.
public struct BatteryReading: Equatable, Sendable {
    public let id: String
    public let name: String
    public let level: Int?
    public let isWired: Bool

    public init(id: String, name: String, level: Int?, isWired: Bool = false) {
        self.id = id
        self.name = name
        self.level = level
        self.isWired = isWired
    }
}

public enum BatteryTier: Equatable, Sendable {
    case critical, low, normal

    public init(level: Int) {
        switch level {
        case ...10: self = .critical
        case 11...30: self = .low
        default: self = .normal
        }
    }
}

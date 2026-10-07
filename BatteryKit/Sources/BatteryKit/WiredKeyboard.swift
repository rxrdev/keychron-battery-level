/// A Keychron keyboard on a USB cable. Stock firmware reports no battery level
/// over USB (it doesn't measure it while wired), so this only marks the cable state.
/// Only keyboards also paired over Bluetooth count: they are the ones with a
/// battery to show, and it leaves out the Keychron Link receiver.
public enum WiredKeyboard {
    public static let keychronVendorID = 0x3434

    public static func reading(vendorID: Int, productName: String?, locationID: Int, isAttached: Bool, pairedNames: Set<String>) -> BatteryReading? {
        guard vendorID == keychronVendorID, let productName, pairedNames.contains(productName) else { return nil }
        return BatteryReading(id: "usb-\(locationID)", name: productName, level: nil, isWired: isAttached)
    }
}

/// Remembers which USB registry entry produced which reading, so an unplug is
/// reported from what was seen at plug-in rather than from a terminated device.
public struct WiredKeyboardTracker {
    private var attached: [UInt64: BatteryReading] = [:]

    public init() {}

    public mutating func attached(entryID: UInt64, reading: BatteryReading) {
        attached[entryID] = reading
    }

    /// The device as unplugged, or nil if this entry was never reported.
    public mutating func detached(entryID: UInt64) -> BatteryReading? {
        attached.removeValue(forKey: entryID).map { BatteryReading(id: $0.id, name: $0.name, level: nil, isWired: false) }
    }
}

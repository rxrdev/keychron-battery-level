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

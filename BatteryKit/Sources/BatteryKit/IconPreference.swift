/// UserDefaults keys for a device's menu bar icon. Keyed by name, because one
/// physical device can arrive under several source ids (BLE, IORegistry, HID).
public enum IconPreference {
    public static func storageKey(for device: Device) -> String {
        "icon_name_\(device.name)"
    }

    /// Name key first, then the per-id key earlier versions stored.
    public static func lookupKeys(for device: Device) -> [String] {
        [storageKey(for: device), "icon_\(device.id)"]
    }
}

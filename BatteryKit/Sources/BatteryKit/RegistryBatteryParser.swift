import Foundation

/// Turns IORegistry entries carrying `BatteryPercent` (Bluetooth Classic HID
/// devices such as the Keychron K3 V2) into battery readings.
public enum RegistryBatteryParser {
    public static func readings(
        from entries: [(entryID: UInt64, properties: [String: Any])],
        previousIDs: Set<String>
    ) -> [BatteryReading] {
        var seen = Set<String>()
        var result: [BatteryReading] = []

        for entry in entries {
            guard let name = entry.properties["Product"] as? String,
                  let level = (entry.properties["BatteryPercent"] as? NSNumber)?.intValue else { continue }

            let address = entry.properties["DeviceAddress"] as? String
            let id = "registry-\(address ?? String(entry.entryID))"
            guard seen.insert(id).inserted else { continue }

            result.append(BatteryReading(id: id, name: name, level: level))
        }

        for id in previousIDs.subtracting(seen).sorted() {
            result.append(BatteryReading(id: id, name: "", level: nil))
        }

        return result
    }
}

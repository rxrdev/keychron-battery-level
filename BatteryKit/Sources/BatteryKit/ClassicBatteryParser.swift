/// A paired Bluetooth Classic device as IOBluetooth reports it. A battery
/// percent of 0 means macOS has no level for it (LE devices always read 0).
public struct ClassicDevice: Codable, Equatable, Sendable {
    public let address: String
    public let name: String
    public let isConnected: Bool
    public let batteryPercent: Int

    public init(address: String, name: String, isConnected: Bool, batteryPercent: Int) {
        self.address = address
        self.name = name
        self.isConnected = isConnected
        self.batteryPercent = batteryPercent
    }
}

/// Turns IOBluetooth devices (headsets, Bluetooth Classic keyboards such as
/// probably the Keychron K3 V2) into battery readings.
public enum ClassicBatteryParser {
    public static func readings(from devices: [ClassicDevice], previousIDs: Set<String>) -> [BatteryReading] {
        var seen = Set<String>()
        var result: [BatteryReading] = []

        for device in devices where device.isConnected {
            let id = "classic-\(device.address)"
            guard seen.insert(id).inserted else { continue }
            // 0 while connected means no fresh value; post nothing so the last level stays
            guard (1...100).contains(device.batteryPercent) else { continue }
            result.append(BatteryReading(id: id, name: device.name, level: device.batteryPercent))
        }

        for id in previousIDs.subtracting(seen).sorted() {
            result.append(BatteryReading(id: id, name: "", level: nil))
        }

        return result
    }
}

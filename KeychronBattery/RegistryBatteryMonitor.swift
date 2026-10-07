import BatteryKit
import Foundation
import IOKit
import os

/// Reads `BatteryPercent` from the IORegistry. macOS publishes it for Bluetooth
/// Classic HID devices (e.g. Keychron K3 V2) that CoreBluetooth cannot see.
final class RegistryBatteryMonitor {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery", category: "RegistryBatteryMonitor")
    private var previousIDs: Set<String> = []

    func requestBatteryUpdate() {
        var iterator: io_iterator_t = 0
        let result = IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
        guard result == KERN_SUCCESS else {
            logger.error("❌ Failed to walk the IORegistry: \(result)")
            return
        }
        defer { IOObjectRelease(iterator) }

        var entries: [(entryID: UInt64, properties: [String: Any])] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let properties = batteryProperties(of: entry) {
                var entryID: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(entry, &entryID)
                entries.append((entryID: entryID, properties: properties))
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        logger.info("🔎 Found \(entries.count) IORegistry entries with BatteryPercent")

        let readings = RegistryBatteryParser.readings(from: entries, previousIDs: previousIDs)
        previousIDs = Set(readings.filter { $0.level != nil }.map(\.id))

        for reading in readings {
            NotificationCenter.default.post(name: .didUpdateBatteryReading, object: reading)
        }
    }

    /// The entry's properties if it carries `BatteryPercent`, with `Product` and
    /// `DeviceAddress` filled in from its parents when the entry lacks them.
    private func batteryProperties(of entry: io_registry_entry_t) -> [String: Any]? {
        // Reading NVRAM variables is denied by the sandbox and logs a kernel violation
        guard !className(of: entry).hasPrefix("IODTNVRAM"),
              IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0) != nil else { return nil }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              var properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        for key in ["Product", "DeviceAddress"] where properties[key] == nil {
            properties[key] = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                key as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            )
        }

        return properties
    }

    private func className(of entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &name)
        return String(cString: name)
    }
}

import BatteryKit
import Foundation
import IOBluetooth
import os

/// Reads battery levels macOS keeps for paired Bluetooth Classic devices
/// (headsets, Keychron K3 V2) that CoreBluetooth cannot see.
final class ClassicBatteryMonitor {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery", category: "ClassicBatteryMonitor")
    // Undocumented IOBluetoothDevice property; checked before every read
    private let batteryKey = "batteryPercentSingle"
    private var previousIDs: Set<String> = []

    func requestBatteryUpdate() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []

        let devices = paired.compactMap { device -> ClassicDevice? in
            guard device.responds(to: NSSelectorFromString(batteryKey)),
                  let percent = device.value(forKey: batteryKey) as? Int,
                  let address = device.addressString else { return nil }
            return ClassicDevice(
                address: address,
                name: device.name ?? "Unknown",
                isConnected: device.isConnected(),
                batteryPercent: percent
            )
        }

        let readings = ClassicBatteryParser.readings(from: devices, previousIDs: previousIDs)
        logger.info("🎧 \(paired.count) paired Bluetooth devices, \(readings.filter { $0.level != nil }.count) with a battery level")
        previousIDs = Set(readings.filter { $0.level != nil }.map(\.id))

        for reading in readings {
            NotificationCenter.default.post(name: .didUpdateBatteryReading, object: reading)
        }
    }
}

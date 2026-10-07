import BatteryKit
import Foundation
import IOBluetooth
import os

/// Reads battery levels macOS keeps for paired Bluetooth Classic devices
/// (headsets, and likely the Keychron K3 V2) that CoreBluetooth cannot see.
///
/// IOBluetooth resets a running process's battery value to 0 on the first level
/// change and never updates it again; a new process reads the right value. So
/// each update runs this app's own executable with `snapshotArgument`, which
/// prints the devices as JSON and exits before any UI starts.
final class ClassicBatteryMonitor: NSObject {
    nonisolated static let snapshotArgument = "--read-classic-batteries"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery", category: "ClassicBatteryMonitor")
    private var previousIDs: Set<String> = []
    private var isReading = false
    private var connectNotification: IOBluetoothUserNotification?

    /// Refreshes when a Classic device connects or disconnects, so headsets put
    /// away or taken out don't wait for the 5-minute timer.
    func start() {
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // The battery level arrives a few seconds after the link comes up
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.requestBatteryUpdate()
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        requestBatteryUpdate()
    }

    func requestBatteryUpdate() {
        guard !isReading, let executable = Bundle.main.executableURL else { return }
        isReading = true

        DispatchQueue.global(qos: .utility).async { [logger] in
            let devices = Self.readSnapshot(executable: executable, logger: logger)
            DispatchQueue.main.async { [weak self] in
                self?.isReading = false
                if let devices {
                    self?.post(devices)
                }
            }
        }
    }

    private func post(_ devices: [ClassicDevice]) {
        for device in devices {
            logger.debug("  • \(device.name, privacy: .public): connected=\(device.isConnected), battery=\(device.batteryPercent)")
        }

        let readings = ClassicBatteryParser.readings(from: devices, previousIDs: previousIDs)
        logger.info("🎧 \(devices.count) paired Bluetooth devices, \(readings.filter { $0.level != nil }.count) with a battery level")

        // A connected device reading 0 posts nothing but stays known, so a later disconnect is reported
        previousIDs.formUnion(readings.filter { $0.level != nil }.map(\.id))
        previousIDs.subtract(readings.filter { $0.level == nil }.map(\.id))

        for reading in readings {
            NotificationCenter.default.post(name: .didUpdateBatteryReading, object: reading)
        }
    }

    private nonisolated static func readSnapshot(executable: URL, logger: Logger) -> [ClassicDevice]? {
        let process = Process()
        process.executableURL = executable
        process.arguments = [snapshotArgument]
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
        } catch {
            logger.error("❌ Failed to start battery snapshot: \(error.localizedDescription)")
            return nil
        }

        let timeout = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        guard process.terminationStatus == 0 else {
            logger.error("❌ Battery snapshot exited with status \(process.terminationStatus)")
            return nil
        }
        return try? JSONDecoder().decode([ClassicDevice].self, from: data)
    }

    /// Runs in the short-lived child process: prints paired devices as JSON.
    nonisolated static func printSnapshot() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        // Undocumented IOBluetoothDevice property; checked before every read
        let batteryKey = "batteryPercentSingle"

        let devices = paired.compactMap { device -> ClassicDevice? in
            guard device.responds(to: NSSelectorFromString(batteryKey)),
                  let percent = device.value(forKey: batteryKey) as? Int,
                  let address = device.addressString,
                  let name = device.name else { return nil }
            return ClassicDevice(address: address, name: name, isConnected: device.isConnected(), batteryPercent: percent)
        }

        if let data = try? JSONEncoder().encode(devices) {
            FileHandle.standardOutput.write(data)
        }
    }
}

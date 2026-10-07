import BatteryKit
import Foundation
import IOBluetooth
import IOKit
import IOKit.usb
import os

/// Reports Keychron keyboards plugged in over USB. Reads only IORegistry
/// properties, so it needs no USB entitlement and never talks to the keyboard.
final class WiredKeyboardMonitor {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery", category: "WiredKeyboardMonitor")
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    func start() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            logger.error("❌ Failed to create IOKit notification port")
            return
        }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for (type, isAttached) in [(kIOFirstMatchNotification, true), (kIOTerminatedNotification, false)] {
            let matching = IOServiceMatching(kIOUSBHostDeviceClassName) as NSMutableDictionary
            // IOUSBHostDevice ignores a top-level idVendor key; it has to go under IOPropertyMatch
            matching[kIOPropertyMatchKey] = [kUSBVendorID: WiredKeyboard.keychronVendorID]

            var iterator: io_iterator_t = 0
            let callback: IOServiceMatchingCallback = isAttached
                ? { context, iterator in WiredKeyboardMonitor.from(context).handle(iterator, isAttached: true) }
                : { context, iterator in WiredKeyboardMonitor.from(context).handle(iterator, isAttached: false) }
            let result = IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator)
            guard result == KERN_SUCCESS else {
                logger.error("❌ Failed to watch USB devices: \(result)")
                continue
            }
            iterators.append(iterator)
            // Draining the iterator arms the notification and reports devices already attached
            handle(iterator, isAttached: isAttached)
        }
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> WiredKeyboardMonitor {
        Unmanaged<WiredKeyboardMonitor>.fromOpaque(context!).takeUnretainedValue()
    }

    private func handle(_ iterator: io_iterator_t, isAttached: Bool) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vendorID = property(kUSBVendorID, of: service) as? Int ?? 0
            let productName = property(kUSBProductString, of: service) as? String
            let locationID = property(kUSBDevicePropertyLocationID, of: service) as? Int ?? 0

            // Names stay current in a long-running process; only IOBluetooth battery values go stale
            let pairedNames = Set((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap(\.name))
            guard let reading = WiredKeyboard.reading(
                vendorID: vendorID,
                productName: productName,
                locationID: locationID,
                isAttached: isAttached,
                pairedNames: pairedNames
            ) else { continue }

            logger.info("🔌 \(reading.name, privacy: .public) \(isAttached ? "plugged in" : "unplugged", privacy: .public)")
            NotificationCenter.default.post(name: .didUpdateBatteryReading, object: reading)
        }
    }

    private func property(_ key: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    deinit {
        iterators.forEach { IOObjectRelease($0) }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
    }
}

//
//  AppDelegate.swift
//  KeychronBattery
//
//  Created by Razvan on 19.12.2025.
//

import BatteryKit
import Cocoa
import ServiceManagement
import os

@main
class AppDelegate: NSObject, NSApplicationDelegate {
   private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery", category: "AppDelegate")

    let bluetoothMonitor = BluetoothBatteryMonitor()
    let hidManager = HIDManager()
    let registryMonitor = RegistryBatteryMonitor()
    let classicMonitor = ClassicBatteryMonitor()

    var statusMenuController: StatusMenuController?

    private var startupRetryCount = 0

    static func main() {
        if CommandLine.arguments.contains(ClassicBatteryMonitor.snapshotArgument) {
            ClassicBatteryMonitor.printSnapshot()
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        statusMenuController = StatusMenuController(appDelegate: self)

        NotificationCenter.default.addObserver(forName: .didUpdateBatteryReading, object: nil, queue: .main) { [weak self] notification in
            if let reading = notification.object as? BatteryReading {
                self?.logger.info("Received battery update for \(reading.name): \(reading.level.map { "\($0)%" } ?? "disconnected")")
                self?.statusMenuController?.apply(reading)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.bluetoothMonitor.start()
            self.classicMonitor.start()
            self.scheduleStartupRetries()
        }

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func scheduleStartupRetries() {
        // Retry every 10 seconds for the first 2 minutes (12 times) to catch devices connecting after boot
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.startupRetryCount += 1

            if self.startupRetryCount > 12 {
                timer.invalidate()
                self.logger.info("Startup retries finished.")
            } else {
                self.logger.info("Startup retry #\(self.startupRetryCount)")
                self.refresh()
            }
        }
    }

    @objc func refresh() {
        logger.info("Refreshing battery status...")
        bluetoothMonitor.requestBatteryUpdate()
        hidManager.requestBatteryUpdate()
        registryMonitor.requestBatteryUpdate()
        classicMonitor.requestBatteryUpdate()
    }

    func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, including when the user switched it off in System Settings
    /// (`.requiresApproval`); unregistering is the only way out of that state.
    func isLaunchAtLoginRegistered() -> Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            logger.info("✅ Enabled launch at login")
        } catch {
            logger.error("❌ Failed to enable launch at login: \(error.localizedDescription)")
        }
    }

    func disableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("✅ Disabled launch at login")
        } catch {
            logger.error("❌ Failed to disable launch at login: \(error.localizedDescription)")
        }
    }
}

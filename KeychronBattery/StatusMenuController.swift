import BatteryKit
import Cocoa

class StatusMenuController: NSObject {
    private var statusItem: NSStatusItem!
    private let batteryIconSize = NSSize(width: 18, height: 18)

    private static let iconChoices = [
        ("keyboard", "Keyboard"),
        ("mouse", "Mouse"),
        ("gamecontroller", "Gamepad"),
        ("headphones", "Headphones")
    ]

    private var store = DeviceStore()
    private var deviceMenuItems: [String: NSMenuItem] = [:]
    private var launchItem: NSMenuItem!
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Setup default icon state
            if let customIcon = NSImage(named: "MenuBarIcon") {
                customIcon.isTemplate = true
                customIcon.size = batteryIconSize
                button.image = customIcon
            }
            button.title = " --%"
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Refresh Item
        let refreshItem = NSMenuItem(title: "Refresh Battery", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login Item
        launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchClicked(_:)), keyEquivalent: "")
        launchItem.target = self
        // Set initial state based on delegate's logic
        launchItem.state = (appDelegate?.isLaunchAtLoginEnabled() ?? false) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit Item
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu
    }

    func apply(_ reading: BatteryReading) {
        store.apply(reading)
        rebuildDeviceMenuItems()
        updateMainStatusItem()
    }

    private func iconName(for device: Device) -> String {
        IconPreference.lookupKeys(for: device).lazy.compactMap { UserDefaults.standard.string(forKey: $0) }.first ?? "keyboard"
    }

    private func rebuildDeviceMenuItems() {
        guard let menu = statusItem.menu else { return }

        deviceMenuItems.values.forEach(menu.removeItem)
        deviceMenuItems.removeAll()

        // Device items go between Refresh and the first separator, sorted by name
        var index = menu.items.firstIndex(where: { $0.isSeparatorItem }) ?? 0

        for device in store.visibleDevices {
            let icon = iconName(for: device)
            let status = statusText(for: device) ?? "Disconnected"
            let item = NSMenuItem(title: "\(iconForName(icon)) \(device.name): \(status)", action: nil, keyEquivalent: "")

            let submenu = NSMenu()
            for (iconKey, iconLabel) in Self.iconChoices {
                let iconItem = NSMenuItem(title: iconLabel, action: #selector(changeIconClicked(_:)), keyEquivalent: "")
                iconItem.target = self
                iconItem.representedObject = ["key": IconPreference.storageKey(for: device), "icon": iconKey]
                iconItem.state = (icon == iconKey) ? .on : .off
                submenu.addItem(iconItem)
            }
            item.submenu = submenu

            menu.insertItem(item, at: index)
            index += 1
            deviceMenuItems[device.id] = item
        }
    }

    private func updateMainStatusItem() {
        guard let button = statusItem.button else { return }

        let activeDevices = store.visibleDevices.compactMap { device in
            statusText(for: device).map { (device: device, status: $0, icon: iconForName(iconName(for: device))) }
        }

        // Set tooltip to show all devices on hover
        let tooltipLines = activeDevices.map { "\($0.icon) \($0.device.name): \($0.status)" }
        button.toolTip = tooltipLines.isEmpty ? nil : tooltipLines.joined(separator: "\n")

        if activeDevices.isEmpty {
            button.attributedTitle = NSAttributedString(string: " --%")
            // Reset to default icon if no devices
            if let customIcon = NSImage(named: "MenuBarIcon") {
                customIcon.isTemplate = true
                customIcon.size = batteryIconSize
                button.image = customIcon
            }
            return
        }

        // Build attributed string with all devices
        let fullAttributedTitle = NSMutableAttributedString()

        for (index, active) in activeDevices.enumerated() {
            if index > 0 {
                fullAttributedTitle.append(NSAttributedString(string: "  ", attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
            }

            let color: NSColor
            switch active.device.level.map(BatteryTier.init(level:)) {
            case .critical: color = .systemRed
            case .low:      color = .systemOrange
            case .normal, nil: color = .labelColor
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.menuBarFont(ofSize: 0)
            ]

            fullAttributedTitle.append(NSAttributedString(string: "\(active.icon) \(active.status)", attributes: attributes))
        }

        button.image = nil // Clear image to rely on emoji in text
        button.attributedTitle = fullAttributedTitle
    }

    /// "57%", or "USB" for a keyboard on its cable (no battery reading there); nil when disconnected.
    private func statusText(for device: Device) -> String? {
        if let level = device.level { return "\(level)%" }
        return device.isWired ? "USB" : nil
    }

    private func iconForName(_ name: String) -> String {
        switch name {
        case "keyboard": return "⌨️"
        case "mouse": return "🖱️"
        case "gamecontroller": return "🎮"
        case "headphones": return "🎧"
        default: return "🔋"
        }
    }

    @objc private func refreshClicked() {
        appDelegate?.refresh()
    }

    @objc private func toggleLaunchClicked(_ sender: NSMenuItem) {
        guard let delegate = appDelegate else { return }

        if delegate.isLaunchAtLoginRegistered() {
            delegate.disableLaunchAtLogin()
        } else {
            delegate.enableLaunchAtLogin()
        }

        // Show what macOS reports, not what was clicked, in case the call failed
        sender.state = delegate.isLaunchAtLoginEnabled() ? .on : .off
    }

    @objc private func changeIconClicked(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: String],
              let key = data["key"],
              let icon = data["icon"] else { return }

        UserDefaults.standard.set(icon, forKey: key)

        rebuildDeviceMenuItems()
        updateMainStatusItem()
    }
}

extension StatusMenuController: NSMenuDelegate {
    // Login items can be changed in System Settings while the app runs
    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem.state = (appDelegate?.isLaunchAtLoginEnabled() ?? false) ? .on : .off
    }
}

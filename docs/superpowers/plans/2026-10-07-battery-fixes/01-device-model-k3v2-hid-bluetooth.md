# Battery Fixes, Part 1 of 2: Device Model, K3 V2, HID, Bluetooth

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the significant defects found in the codebase review and show the battery level of Bluetooth Classic keyboards such as the Keychron K3 V2.

**Architecture:** Pure logic (reading model, device store, report parsers) moves into a local Swift package `BatteryKit` that runs under `swift test` without signing, Bluetooth or a host app. The app links it. Every battery source (CoreBluetooth, raw HID, and a new IORegistry source) posts one notification carrying a `BatteryReading`; `StatusMenuController` renders a `DeviceStore`.

**Tech Stack:** Swift 6.3 toolchain (package in Swift 6 language mode, app stays Swift 5 mode), Swift Testing, AppKit, CoreBluetooth, IOKit HID, Xcode 26.6.

**Spec:** No spec document. This plan argues from (a) the codebase review in this session and (b) the user report "I will like a lot to see battery level of my K3 V2".

**Part 2** (`02-…`, written next) covers: deployment target 15.7 → 13.0 and removing the dead `#available` fallbacks; `MARKETING_VERSION` from the release tag; README corrections; untracking the committed DMG, `project.pbxproj.backup` and `xcuserdata`.

## Why the K3 V2 does not show today

The K3 V2 (non-QMK, pre-"Pro") connects over Bluetooth Classic HID. CoreBluetooth only sees Bluetooth Low Energy peripherals, so `retrieveConnectedPeripherals` never returns it. The K2 HE on this Mac shows `Services: < BLE >` in `system_profiler`, which is why it works. For Classic HID devices that report a battery level, macOS publishes a `BatteryPercent` property in the IORegistry (that is what `ioreg -r -l -k BatteryPercent` lists). Task 2 reads that property.

**Known unknown:** whether the K3 V2 reports its battery to macOS at all. If the reporter's `ioreg` dump has no `BatteryPercent` for the keyboard, macOS never receives the value and no app can read it this way. Task 2 Step 1 gets that answer before any code is written.

## Global Constraints

- App target: Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (unchanged).
- `BatteryKit` platforms: `.macOS(.v13)` (Part 2 lowers the app to 13.0; the package must not block that).
- `BatteryKit` imports Foundation only. No AppKit, IOKit or CoreBluetooth in the package.
- Bundle id and logger subsystem stay `Bundle.main.bundleIdentifier ?? "dev.rrazvan.keychron.battery"`.
- Battery tiers (unchanged): 0–10 red, 11–30 orange, above 30 label color.
- App build command (used for every verification):
  `xcodebuild -project KeychronBattery.xcodeproj -scheme KeychronBattery -configuration Release -derivedDataPath ./build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build`
- Package test command: `swift test --package-path BatteryKit`
- Log stream for manual checks: `log stream --level debug --predicate 'subsystem == "dev.rrazvan.KeychronBattery"'`
- SwiftLint must pass (it runs in the build phase).

## Review Focus

1. **A keyboard whose battery macOS never receives** (K3 V2 if the dump has no `BatteryPercent`): no menu entry, no crash, no "0%". Test: `registryEntryWithoutBatteryPercentIsSkipped` (Task 2).
2. **A source reporting a level outside 0–100** (BLE devices send 255 for "unknown"): shown as unknown, never "255%". Test: `outOfRangeLevelIsTreatedAsUnknown` (Task 1).
3. **The same keyboard reported by two sources** (BLE + IORegistry, or BLE + wired HID): one entry in the menu bar. Test: `sameNameFromTwoSourcesShowsOnce` (Task 1).
4. **A device that disappears** (unplugged, switched off, out of range): its entry flips to "Disconnected" instead of keeping the last level. Tests: `vanishedRegistryDeviceReportsDisconnected` (Task 2), `nilLevelKeepsDeviceButHidesItFromStatusBar` (Task 1); HID and BLE paths checked manually in Tasks 3 and 4.
5. **Raw HID traffic arriving outside a battery scan** (the keyboard's own raw HID reports): ignored, not read as a battery level. Test: `reportOutsideScanIsIgnored` (Task 3).

---

### Task 1: BatteryKit package, unified reading, device store

**Files:**
- Create: `BatteryKit/Package.swift`
- Create: `BatteryKit/Sources/BatteryKit/BatteryReading.swift`
- Create: `BatteryKit/Sources/BatteryKit/DeviceStore.swift`
- Create: `BatteryKit/Tests/BatteryKitTests/DeviceStoreTests.swift`
- Modify: `KeychronBattery.xcodeproj/project.pbxproj` (link the package)
- Modify: `KeychronBattery/StatusMenuController.swift` (render from `DeviceStore`)
- Modify: `KeychronBattery/AppDelegate.swift:34-50` (one observer)
- Modify: `KeychronBattery/BluetoothBatteryHelper.swift:5-7,158-171` (post `BatteryReading`)
- Modify: `KeychronBattery/HIDManager.swift:5-7,197-199` (post `BatteryReading`)
- Modify: `.swiftlint.yml` (add `BatteryKit` to `included`)

**Interfaces:**
- Produces:
  - `public struct BatteryReading: Equatable, Sendable { public let id: String; public let name: String; public let level: Int?; public init(id: String, name: String, level: Int?) }` — `level == nil` means disconnected or unknown.
  - `extension Notification.Name { public static let didUpdateBatteryReading }` — posted on the main queue with `object: BatteryReading`.
  - `public struct DeviceStore { public init(); public mutating func apply(_ reading: BatteryReading); public var visibleDevices: [Device] { get } }`
  - `public struct Device: Equatable, Sendable { public let id: String; public let name: String; public let level: Int? }`
  - `public enum BatteryTier: Equatable, Sendable { case critical, low, normal; public init(level: Int) }`

- [ ] **Step 1: Create `BatteryKit/Package.swift`**

`// swift-tools-version: 6.0`, one library product and target `BatteryKit`, one test target `BatteryKitTests`, `platforms: [.macOS(.v13)]`.

- [ ] **Step 2: Write the failing tests in `DeviceStoreTests.swift`** (Swift Testing)

```swift
@Test func applyAddsDevice() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "a", name: "K2 HE", level: 80))
    #expect(store.visibleDevices == [Device(id: "a", name: "K2 HE", level: 80)])
}

@Test func nilLevelKeepsDeviceButHidesItFromStatusBar() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "a", name: "K2 HE", level: 80))
    store.apply(BatteryReading(id: "a", name: "K2 HE", level: nil))
    #expect(store.visibleDevices.map(\.level) == [nil])
}

@Test func outOfRangeLevelIsTreatedAsUnknown() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "a", name: "Mouse", level: 255))
    store.apply(BatteryReading(id: "b", name: "Pad", level: -3))
    #expect(store.visibleDevices.map(\.level) == [nil, nil])
}

@Test func sameNameFromTwoSourcesShowsOnce() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "ble-1", name: "Keychron K3", level: 70))
    store.apply(BatteryReading(id: "registry-x", name: "Keychron K3", level: 72))
    #expect(store.visibleDevices == [Device(id: "registry-x", name: "Keychron K3", level: 72)])
    store.apply(BatteryReading(id: "registry-x", name: "Keychron K3", level: nil))
    #expect(store.visibleDevices == [Device(id: "ble-1", name: "Keychron K3", level: 70)])
}

@Test func visibleDevicesAreSortedByName() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "2", name: "MX Master 3S", level: 40))
    store.apply(BatteryReading(id: "1", name: "Keychron K2 HE", level: 90))
    #expect(store.visibleDevices.map(\.name) == ["Keychron K2 HE", "MX Master 3S"])
}

@Test(arguments: [(0, BatteryTier.critical), (10, .critical), (11, .low), (30, .low), (31, .normal), (100, .normal)])
func tierThresholds(level: Int, tier: BatteryTier) {
    #expect(BatteryTier(level: level) == tier)
}
```

- [ ] **Step 3: Run `swift test --package-path BatteryKit`**

Expected: compile failure, `cannot find 'DeviceStore' in scope`.

- [ ] **Step 4: Implement `BatteryReading.swift` and `DeviceStore.swift`**

`apply` stores levels outside `0...100` as `nil`. `visibleDevices` groups by `name`; within a group it picks a connected device (non-nil level) over a disconnected one, and among equals the most recently applied (keep a monotonically increasing counter per stored device). Result sorted by `name`.

- [ ] **Step 5: Run `swift test --package-path BatteryKit`**

Expected: all `DeviceStoreTests` pass.

- [ ] **Step 6: Link the package into the app target in `project.pbxproj`**

Add, with fresh 24-hex-character IDs:
- an `XCLocalSwiftPackageReference` section with one entry `{isa = XCLocalSwiftPackageReference; relativePath = BatteryKit; }`, listed in the `PBXProject` object as `packageReferences = ( <ref> );`
- an `XCSwiftPackageProductDependency` section with one entry `{isa = XCSwiftPackageProductDependency; productName = BatteryKit; }`, listed in the target's `packageProductDependencies`
- a `PBXBuildFile` section with `{isa = PBXBuildFile; productRef = <dependency>; }`, listed in the `Frameworks` build phase `files`

Do not touch `project.pbxproj.backup`; Part 2 removes it.

- [ ] **Step 7: Switch the app to `BatteryReading` and `DeviceStore`**

- Delete `.didUpdateBluetoothBattery` and `.didReceiveBatteryLevel`. `BluetoothBatteryMonitor.notifyBatteryUpdate` posts `.didUpdateBatteryReading` with `BatteryReading(id: peripheral.identifier.uuidString, name:, level:)`, where disconnect passes `nil` instead of `-1`. `HIDManager` posts `BatteryReading(id: "HID-DEVICE-001", name: "Wired/HID Device", level: battery)` for now (Task 3 replaces the id).
- `AppDelegate` keeps one observer for `.didUpdateBatteryReading` that calls `statusMenuController?.apply(_ reading: BatteryReading)`.
- `StatusMenuController` replaces `devices: [String: DeviceInfo]` with `private var store = DeviceStore()`. `apply(_:)` calls `store.apply` and then rebuilds the device menu items and the status title from `store.visibleDevices`. Icons stay in `UserDefaults` under `icon_<id>`. Color comes from `BatteryTier(level:)`. Menu items for ids no longer in `visibleDevices` are removed.
- The icon submenu iterates an ordered array `[("keyboard", "Keyboard"), ("mouse", "Mouse"), ("gamecontroller", "Gamepad"), ("headphones", "Headphones")]` so its order is stable.

- [ ] **Step 8: Build the app**

Run the app build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`, no SwiftLint errors.

- [ ] **Step 9: Manual check**

Launch `build/Build/Products/Release/KeychronBattery.app`. Expected: the K2 HE and MX Master 3S appear in the menu bar with levels, the menu lists both, and the icon submenu order is Keyboard, Mouse, Gamepad, Headphones.

- [ ] **Step 10: Commit**

```bash
git add BatteryKit .swiftlint.yml KeychronBattery.xcodeproj/project.pbxproj KeychronBattery/*.swift
git commit -m "refactor: unify battery readings in a tested BatteryKit device store"
```

---

### Task 2: IORegistry battery source (K3 V2 and other Bluetooth Classic devices)

**Files:**
- Create: `BatteryKit/Sources/BatteryKit/RegistryBatteryParser.swift`
- Create: `BatteryKit/Tests/BatteryKitTests/RegistryBatteryParserTests.swift`
- Create: `KeychronBattery/RegistryBatteryMonitor.swift`
- Modify: `KeychronBattery/AppDelegate.swift` (own the monitor, call it from `refresh()`)

**Interfaces:**
- Consumes: `BatteryReading`, `.didUpdateBatteryReading` (Task 1).
- Produces:
  - `public enum RegistryBatteryParser { public static func readings(from entries: [(entryID: UInt64, properties: [String: Any])], previousIDs: Set<String>) -> [BatteryReading] }`
  - `final class RegistryBatteryMonitor { func requestBatteryUpdate() }`

- [ ] **Step 1: Get the reporter's data**

Ask the person who reported the K3 V2 issue to run, with the keyboard connected over Bluetooth:

```bash
ioreg -r -l -k BatteryPercent
system_profiler SPBluetoothDataType
```

and to say whether Control Center → Bluetooth shows a battery percentage for the K3 V2.

- If the output has an entry with `"BatteryPercent"` and a `"Product"` naming the K3: copy that entry's `Product`, `BatteryPercent` and `DeviceAddress` values into the fixture in Step 2 and continue.
- If there is no `BatteryPercent` entry for it: stop this task and report that macOS does not receive the K3 V2's battery level. Continue with Task 3.

- [ ] **Step 2: Write the failing tests in `RegistryBatteryParserTests.swift`**

The fixture below is a placeholder shape until Step 1 supplies real values.

```swift
let k3: [String: Any] = ["Product": "Keychron K3", "BatteryPercent": 72, "DeviceAddress": "dc-2c-26-00-00-01"]

@Test func readsBatteryPercent() {
    let r = RegistryBatteryParser.readings(from: [(entryID: 42, properties: k3)], previousIDs: [])
    #expect(r == [BatteryReading(id: "registry-dc-2c-26-00-00-01", name: "Keychron K3", level: 72)])
}

@Test func fallsBackToEntryIDWhenAddressMissing() {
    var p = k3; p["DeviceAddress"] = nil
    let r = RegistryBatteryParser.readings(from: [(entryID: 42, properties: p)], previousIDs: [])
    #expect(r.map(\.id) == ["registry-42"])
}

@Test func registryEntryWithoutBatteryPercentIsSkipped() {
    var p = k3; p["BatteryPercent"] = nil
    #expect(RegistryBatteryParser.readings(from: [(entryID: 42, properties: p)], previousIDs: []).isEmpty)
}

@Test func registryEntryWithoutProductIsSkipped() {
    var p = k3; p["Product"] = nil
    #expect(RegistryBatteryParser.readings(from: [(entryID: 42, properties: p)], previousIDs: []).isEmpty)
}

@Test func vanishedRegistryDeviceReportsDisconnected() {
    let r = RegistryBatteryParser.readings(from: [], previousIDs: ["registry-dc-2c-26-00-00-01"])
    #expect(r == [BatteryReading(id: "registry-dc-2c-26-00-00-01", name: "", level: nil)])
}
```

The vanished reading has an empty name. `DeviceStore.apply` must keep the stored name when a reading's name is empty; add `@Test func emptyNameKeepsStoredName()` to `DeviceStoreTests` for it.

- [ ] **Step 3: Run `swift test --package-path BatteryKit`**

Expected: compile failure, `cannot find 'RegistryBatteryParser' in scope`.

- [ ] **Step 4: Implement `RegistryBatteryParser.readings` and the empty-name rule in `DeviceStore.apply`**

`BatteryPercent` is read as `Int` (IORegistry numbers bridge as `NSNumber`), `Product` and `DeviceAddress` as `String`. Duplicate entries for the same id (one device can expose several services) collapse to one reading.

- [ ] **Step 5: Run `swift test --package-path BatteryKit`**

Expected: all tests pass.

- [ ] **Step 6: Implement `RegistryBatteryMonitor` in `KeychronBattery/RegistryBatteryMonitor.swift`**

`requestBatteryUpdate()` walks the IOService plane with `IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)`. For each entry with a `BatteryPercent` property it collects `IORegistryEntryCreateCFProperties` plus `IORegistryEntryGetRegistryEntryID`. `Product` and `DeviceAddress` are looked up with `IORegistryEntrySearchCFProperty(..., IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))` when the entry itself lacks them. It passes the entries to `RegistryBatteryParser.readings`, posts each result as `.didUpdateBatteryReading`, and stores the ids that had a level as the next `previousIDs`. Release every `io_object_t` with `IOObjectRelease`. Log the count of entries found at `.info`.

`AppDelegate` owns `let registryMonitor = RegistryBatteryMonitor()` and calls `registryMonitor.requestBatteryUpdate()` from `refresh()`, so it runs with the startup retries and the 5-minute timer.

- [ ] **Step 7: Build and check the sandbox allows the walk**

Run the app build command, launch the app, and watch the log stream. Expected: an info line from `RegistryBatteryMonitor` with an entry count and no sandbox denial. On this Mac the count is 0, because the K2 HE and MX Master 3S are BLE. `log show --last 2m --predicate 'sender == "Sandbox"'` shows no `iokit` denial for KeychronBattery.

- [ ] **Step 8: Commit**

```bash
git add BatteryKit KeychronBattery/RegistryBatteryMonitor.swift KeychronBattery/AppDelegate.swift
git commit -m "feat: read battery levels of Bluetooth Classic devices from the IORegistry"
```

- [ ] **Step 9: Reporter confirmation**

Send the reporter a build (or wait for Part 2's release). Done when they confirm the K3 V2 percentage appears and matches Control Center.

---

### Task 3: Raw HID fixes (thread safety, identity, disconnect, Release entitlement)

**Files:**
- Create: `BatteryKit/Sources/BatteryKit/HIDBatteryParser.swift`
- Create: `BatteryKit/Tests/BatteryKitTests/HIDBatteryParserTests.swift`
- Modify: `KeychronBattery/HIDManager.swift`
- Modify: `KeychronBattery.xcodeproj/project.pbxproj` (target build settings, Debug and Release)

**Interfaces:**
- Consumes: `BatteryReading`, `.didUpdateBatteryReading` (Task 1).
- Produces: `public enum HIDBatteryParser { public static func level(fromReport report: [UInt8], scanInProgress: Bool) -> Int? }`

- [ ] **Step 1: Write the failing tests in `HIDBatteryParserTests.swift`**

These pin the existing heuristic (`byte0 == 0x02`, `byte2` in `1...100`) and add the scan gate:

```swift
@Test func readsLevelFromMatchingReport() {
    #expect(HIDBatteryParser.level(fromReport: [0x02, 0x00, 0x55] + Array(repeating: 0, count: 61), scanInProgress: true) == 85)
}
@Test func reportOutsideScanIsIgnored() {
    #expect(HIDBatteryParser.level(fromReport: [0x02, 0x00, 0x55], scanInProgress: false) == nil)
}
@Test func shortReportIsIgnored() {
    #expect(HIDBatteryParser.level(fromReport: [0x02, 0x00], scanInProgress: true) == nil)
}
@Test func otherCommandIsIgnored() {
    #expect(HIDBatteryParser.level(fromReport: [0xFF, 0x00, 0x55], scanInProgress: true) == nil)
}
@Test(arguments: [0, 101, 255])
func outOfRangeByteIsIgnored(byte: Int) {
    #expect(HIDBatteryParser.level(fromReport: [0x02, 0x00, UInt8(byte)], scanInProgress: true) == nil)
}
```

- [ ] **Step 2: Run `swift test --package-path BatteryKit`**

Expected: compile failure, `cannot find 'HIDBatteryParser' in scope`.

- [ ] **Step 3: Implement `HIDBatteryParser.level`**

- [ ] **Step 4: Run `swift test --package-path BatteryKit`**

Expected: all tests pass.

- [ ] **Step 5: Fix `HIDManager`**

- `handleInputReport` calls `HIDBatteryParser.level(fromReport: Array(data), scanInProgress: isSearchingForBattery)`.
- `executeCommandStep` reschedules with `DispatchQueue.main.asyncAfter` instead of `DispatchQueue.global(qos: .background)`, so the command chain, the flag and the IOHID callbacks all run on the main run loop.
- When `setupReceiver` adopts a device, store `rawHIDReadingID = "hid-\(locationID)"`, where `locationID` is `kIOHIDLocationIDKey` as `Int`, falling back to the PID, and `rawHIDName` = `kIOHIDProductKey`, falling back to `"Keychron (wired)"`. Battery readings use these instead of `"HID-DEVICE-001"` / `"Wired/HID Device"`.
- `deviceRemoved` for the active device posts `BatteryReading(id: rawHIDReadingID, name: rawHIDName, level: nil)` before clearing it, and sets `isSearchingForBattery = false`.

- [ ] **Step 6: Enable USB in Release and Bluetooth in Debug**

In the target's build settings: Release `ENABLE_RESOURCE_ACCESS_USB = YES`, Debug `ENABLE_RESOURCE_ACCESS_BLUETOOTH = YES`. Leave everything else as it is.

- [ ] **Step 7: Build and verify the entitlements**

Run the app build command, then:

```bash
codesign -d --entitlements - build/Build/Products/Release/KeychronBattery.app
```

Expected: both `com.apple.security.device.usb` and `com.apple.security.device.bluetooth` are `true`.

- [ ] **Step 8: Manual check with the K2 HE on a USB cable**

Switch the K2 HE to cable mode, launch the app, watch the log stream, and click Refresh Battery. Expected: `Opened HID device directly: Success`, then either `Battery found (N%)` with a menu entry named after the keyboard, or `Finished command sequence. No response from device.` with no menu entry. Unplug the cable. Expected: the entry shows "Disconnected" and leaves the menu bar title. Record which outcome happened in the commit message body; the heuristic is unverified on real hardware.

- [ ] **Step 9: Commit**

```bash
git add BatteryKit KeychronBattery/HIDManager.swift KeychronBattery.xcodeproj/project.pbxproj
git commit -m "fix: run HID battery scan on main loop, report disconnects, allow USB in Release"
```

---

### Task 4: Bluetooth reconnect bookkeeping

**Files:**
- Modify: `KeychronBattery/BluetoothBatteryHelper.swift:12,79-91,153-156,185-214`

**Interfaces:**
- Consumes: `BatteryReading`, `.didUpdateBatteryReading` (Task 1).
- Produces: nothing new.

CoreBluetooth delegates cannot run under `swift test` without a mock layer this app doesn't have, so this task is verified by hand.

- [ ] **Step 1: Keep disconnected peripherals tracked**

Rename `connectedPeripherals` to `trackedPeripherals`. `didDisconnectPeripheral` posts the `nil` reading and calls `centralManager.connect`, but no longer removes the peripheral. Only `didFailToConnect` removes it. `requestBatteryUpdate` already reconnects tracked peripherals that are not `.connected`.

- [ ] **Step 2: Remove the dead discovery path**

Delete `centralManager(_:didDiscover:advertisementData:rssi:)`; nothing calls `scanForPeripherals`.

- [ ] **Step 3: Build**

Run the app build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check with the K2 HE on Bluetooth**

Launch the app and wait for the K2 HE level. Switch the keyboard off. Expected: the menu entry shows "Disconnected" within a few seconds. Switch it back on. Expected: the level returns within 30 seconds without clicking Refresh, and the log shows `Connected to Keychron K2 HE` once, not twice.

- [ ] **Step 5: Commit**

```bash
git add KeychronBattery/BluetoothBatteryHelper.swift
git commit -m "fix: keep Bluetooth peripherals tracked across disconnects"
```

---

### Task 5: IOBluetooth battery source (Bluetooth Classic headsets and keyboards)

Added after Task 4. With Galaxy Buds2 connected, `system_profiler` shows `Battery Level: 100%`, but the IORegistry has no `BatteryPercent` for them. A probe found the value on `IOBluetoothDevice.batteryPercentSingle` (undocumented; 0 means no data, LE devices read 0). The K3 V2 is Bluetooth Classic too, so this is the likelier home of its level.

**Files:**
- Create: `BatteryKit/Sources/BatteryKit/ClassicBatteryParser.swift`
- Create: `BatteryKit/Tests/BatteryKitTests/ClassicBatteryParserTests.swift`
- Create: `KeychronBattery/ClassicBatteryMonitor.swift`
- Modify: `KeychronBattery/AppDelegate.swift` (own the monitor, call it from `refresh()`)

**Interfaces:**
- Consumes: `BatteryReading`, `.didUpdateBatteryReading` (Task 1).
- Produces:
  - `public struct ClassicDevice: Sendable { public let address: String; public let name: String; public let isConnected: Bool; public let batteryPercent: Int; public init(...) }`
  - `public enum ClassicBatteryParser { public static func readings(from devices: [ClassicDevice], previousIDs: Set<String>) -> [BatteryReading] }`
  - `final class ClassicBatteryMonitor { func requestBatteryUpdate() }`

- [ ] **Step 1: Write the failing tests in `ClassicBatteryParserTests.swift`**

```swift
let buds = ClassicDevice(address: "84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", isConnected: true, batteryPercent: 100)

@Test func readsConnectedDeviceWithBattery() {
    #expect(ClassicBatteryParser.readings(from: [buds], previousIDs: []) ==
            [BatteryReading(id: "classic-84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", level: 100)])
}
@Test func zeroPercentMeansNoDataAndIsSkipped()        // LE devices (K2 HE, MX Master) report 0
@Test func disconnectedDeviceIsSkipped()
@Test func vanishedDeviceReportsDisconnected()         // previousIDs has it, devices doesn't → level nil, name ""
@Test func disconnectedDeviceSeenBeforeReportsDisconnected()
```

- [ ] **Step 2: Run `swift test --package-path BatteryKit`** — Expected: `cannot find 'ClassicDevice' in scope`.
- [ ] **Step 3: Implement `ClassicBatteryParser.readings`** — keep connected devices with `batteryPercent` in `1...100`; id `classic-<address>`; ids in `previousIDs` not produced this time get `BatteryReading(id:, name: "", level: nil)`.
- [ ] **Step 4: Run `swift test --package-path BatteryKit`** — Expected: all pass.
- [ ] **Step 5: Implement `ClassicBatteryMonitor`** — iterate `IOBluetoothDevice.pairedDevices()`, read `batteryPercentSingle` via KVC only when `responds(to:)` the selector (undocumented property; absent → skip), post each reading, keep ids with a level as next `previousIDs`. `AppDelegate` calls it from `refresh()`.
- [ ] **Step 6: Build and check** — app build command; launch; expected: menu shows `Galaxy Buds2 (4F69): 100%`, K2 HE and MX Master appear once each, no Sandbox denials for the pid.
- [ ] **Step 7: Commit** — `feat: read battery levels of Bluetooth Classic devices via IOBluetooth`

import Testing
@testable import BatteryKit

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
    store.apply(BatteryReading(id: "a", name: "Mouse", level: 80))
    store.apply(BatteryReading(id: "a", name: "Mouse", level: 255))
    store.apply(BatteryReading(id: "b", name: "Pad", level: -3))
    #expect(store.visibleDevices == [Device(id: "a", name: "Mouse", level: nil)])
}

@Test func sameNameFromTwoSourcesShowsOnce() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "ble-1", name: "Keychron K3", level: 70))
    store.apply(BatteryReading(id: "registry-x", name: "Keychron K3", level: 72))
    #expect(store.visibleDevices == [Device(id: "ble-1", name: "Keychron K3", level: 70)])
    store.apply(BatteryReading(id: "ble-1", name: "Keychron K3", level: nil))
    #expect(store.visibleDevices == [Device(id: "registry-x", name: "Keychron K3", level: 72)])
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

@Test func emptyNameKeepsStoredName() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "a", name: "Keychron K3", level: 72))
    store.apply(BatteryReading(id: "a", name: "", level: nil))
    #expect(store.visibleDevices == [Device(id: "a", name: "Keychron K3", level: nil)])
}

@Test func emptyNameForUnknownIdIsIgnored() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "a", name: "", level: nil))
    #expect(store.visibleDevices.isEmpty)
}

@Test func shownSourceStaysWhileConnected() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "ble-1", name: "Keychron K3", level: 70))
    store.apply(BatteryReading(id: "registry-x", name: "Keychron K3", level: 72))
    store.apply(BatteryReading(id: "ble-1", name: "Keychron K3", level: 69))
    store.apply(BatteryReading(id: "registry-x", name: "Keychron K3", level: 71))
    #expect(store.visibleDevices == [Device(id: "ble-1", name: "Keychron K3", level: 69)])
}

@Test func nilReadingForUnknownIdIsIgnored() {
    var store = DeviceStore()
    store.apply(BatteryReading(id: "hid-1", name: "Keychron Q1", level: nil))
    #expect(store.visibleDevices.isEmpty)
}

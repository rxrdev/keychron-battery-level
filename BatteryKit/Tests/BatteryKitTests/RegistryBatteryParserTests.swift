import Testing
@testable import BatteryKit

// Placeholder shape until the K3 V2 reporter's `ioreg -r -l -k BatteryPercent` dump arrives.
private func k3() -> [String: Any] {
    ["Product": "Keychron K3", "BatteryPercent": 72, "DeviceAddress": "dc-2c-26-00-00-01"]
}

@Test func readsBatteryPercent() {
    let readings = RegistryBatteryParser.readings(from: [(entryID: 42, properties: k3())], previousIDs: [])
    #expect(readings == [BatteryReading(id: "registry-dc-2c-26-00-00-01", name: "Keychron K3", level: 72)])
}

@Test func fallsBackToEntryIDWhenAddressMissing() {
    var properties = k3()
    properties["DeviceAddress"] = nil
    let readings = RegistryBatteryParser.readings(from: [(entryID: 42, properties: properties)], previousIDs: [])
    #expect(readings.map(\.id) == ["registry-42"])
}

@Test func registryEntryWithoutBatteryPercentIsSkipped() {
    var properties = k3()
    properties["BatteryPercent"] = nil
    #expect(RegistryBatteryParser.readings(from: [(entryID: 42, properties: properties)], previousIDs: []).isEmpty)
}

@Test func registryEntryWithoutProductIsSkipped() {
    var properties = k3()
    properties["Product"] = nil
    #expect(RegistryBatteryParser.readings(from: [(entryID: 42, properties: properties)], previousIDs: []).isEmpty)
}

@Test func vanishedRegistryDeviceReportsDisconnected() {
    let readings = RegistryBatteryParser.readings(from: [], previousIDs: ["registry-dc-2c-26-00-00-01"])
    #expect(readings == [BatteryReading(id: "registry-dc-2c-26-00-00-01", name: "", level: nil)])
}

@Test func duplicateEntriesForOneDeviceCollapse() {
    let readings = RegistryBatteryParser.readings(
        from: [(entryID: 42, properties: k3()), (entryID: 43, properties: k3())],
        previousIDs: []
    )
    #expect(readings.count == 1)
}

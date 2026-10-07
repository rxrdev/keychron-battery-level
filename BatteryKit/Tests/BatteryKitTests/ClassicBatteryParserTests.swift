import Testing
@testable import BatteryKit

private let buds = ClassicDevice(address: "84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", isConnected: true, batteryPercent: 100)

@Test func readsConnectedDeviceWithBattery() {
    #expect(ClassicBatteryParser.readings(from: [buds], previousIDs: []) ==
            [BatteryReading(id: "classic-84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", level: 100)])
}

@Test func zeroPercentMeansNoDataAndIsSkipped() {
    let keyboard = ClassicDevice(address: "f1-81", name: "Keychron K2 HE", isConnected: true, batteryPercent: 0)
    #expect(ClassicBatteryParser.readings(from: [keyboard], previousIDs: []).isEmpty)
}

@Test func disconnectedDeviceIsSkipped() {
    let offline = ClassicDevice(address: "84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", isConnected: false, batteryPercent: 100)
    #expect(ClassicBatteryParser.readings(from: [offline], previousIDs: []).isEmpty)
}

@Test func vanishedDeviceReportsDisconnected() {
    #expect(ClassicBatteryParser.readings(from: [], previousIDs: ["classic-84-5f-04-f1-4f-69"]) ==
            [BatteryReading(id: "classic-84-5f-04-f1-4f-69", name: "", level: nil)])
}

@Test func disconnectedDeviceSeenBeforeReportsDisconnected() {
    let offline = ClassicDevice(address: "84-5f-04-f1-4f-69", name: "Galaxy Buds2 (4F69)", isConnected: false, batteryPercent: 100)
    #expect(ClassicBatteryParser.readings(from: [offline], previousIDs: ["classic-84-5f-04-f1-4f-69"]) ==
            [BatteryReading(id: "classic-84-5f-04-f1-4f-69", name: "", level: nil)])
}

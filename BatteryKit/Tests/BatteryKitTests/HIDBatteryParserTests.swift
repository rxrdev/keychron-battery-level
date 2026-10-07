import Testing
@testable import BatteryKit

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

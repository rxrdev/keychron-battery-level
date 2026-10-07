import Testing
@testable import BatteryKit

private let paired: Set<String> = ["Keychron K2 HE", "MX Master 3S"]

@Test func attachedKeychronIsWired() {
    #expect(WiredKeyboard.reading(vendorID: 0x3434, productName: "Keychron K2 HE", locationID: 17_825_792, isAttached: true, pairedNames: paired) ==
            BatteryReading(id: "usb-17825792", name: "Keychron K2 HE", level: nil, isWired: true))
}

@Test func detachedKeychronIsDisconnected() {
    #expect(WiredKeyboard.reading(vendorID: 0x3434, productName: "Keychron K2 HE", locationID: 17_825_792, isAttached: false, pairedNames: paired) ==
            BatteryReading(id: "usb-17825792", name: "Keychron K2 HE", level: nil, isWired: false))
}

@Test func otherVendorIsIgnored() {
    #expect(WiredKeyboard.reading(vendorID: 0x05AC, productName: "Magic Keyboard", locationID: 1, isAttached: true, pairedNames: paired) == nil)
}

@Test func namelessDeviceIsIgnored() {
    #expect(WiredKeyboard.reading(vendorID: 0x3434, productName: nil, locationID: 1, isAttached: true, pairedNames: paired) == nil)
}

@Test func keychronNotPairedOverBluetoothIsIgnored() {
    // The Keychron Link receiver, or a wired-only keyboard with no battery to show
    #expect(WiredKeyboard.reading(vendorID: 0x3434, productName: "Keychron Link", locationID: 2, isAttached: true, pairedNames: paired) == nil)
}

private let plugged = BatteryReading(id: "usb-17825792", name: "Keychron K2 HE", level: nil, isWired: true)

@Test func detachReportsTheCachedDeviceUnplugged() {
    // Properties of a terminated USB device aren't re-read, and pairing may have changed since
    var tracker = WiredKeyboardTracker()
    tracker.attached(entryID: 42, reading: plugged)
    #expect(tracker.detached(entryID: 42) == BatteryReading(id: "usb-17825792", name: "Keychron K2 HE", level: nil, isWired: false))
}

@Test func detachOfUntrackedEntryReportsNothing() {
    var tracker = WiredKeyboardTracker()
    #expect(tracker.detached(entryID: 7) == nil)
}

@Test func detachIsReportedOnce() {
    var tracker = WiredKeyboardTracker()
    tracker.attached(entryID: 42, reading: plugged)
    _ = tracker.detached(entryID: 42)
    #expect(tracker.detached(entryID: 42) == nil)
}

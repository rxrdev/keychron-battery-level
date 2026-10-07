import Testing
@testable import BatteryKit

@Test func iconIsStoredByDeviceName() {
    #expect(IconPreference.storageKey(for: Device(id: "registry-x", name: "Keychron K3", level: 70)) == "icon_name_Keychron K3")
}

@Test func iconLookupPrefersNameThenLegacyId() {
    let device = Device(id: "0A1B-UUID", name: "MX Master 3S", level: 80)
    #expect(IconPreference.lookupKeys(for: device) == ["icon_name_MX Master 3S", "icon_0A1B-UUID"])
}

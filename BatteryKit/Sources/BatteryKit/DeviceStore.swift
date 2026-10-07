public struct Device: Equatable, Sendable {
    public let id: String
    public let name: String
    public let level: Int?

    public init(id: String, name: String, level: Int?) {
        self.id = id
        self.name = name
        self.level = level
    }
}

/// Latest reading per source id, collapsed to one device per name.
public struct DeviceStore {
    private struct Entry {
        var device: Device
        var sequence: Int
    }

    private var entries: [String: Entry] = [:]
    private var sequence = 0

    public init() {}

    /// An empty name keeps the stored one; for an unknown id it is ignored.
    public mutating func apply(_ reading: BatteryReading) {
        guard let name = reading.name.isEmpty ? entries[reading.id]?.device.name : reading.name else { return }

        sequence += 1
        let level = reading.level.flatMap { (0...100).contains($0) ? $0 : nil }
        entries[reading.id] = Entry(device: Device(id: reading.id, name: name, level: level), sequence: sequence)
    }

    /// One device per name, sorted by name. A connected source wins over a
    /// disconnected one; among equals, the most recent reading wins.
    public var visibleDevices: [Device] {
        Dictionary(grouping: entries.values, by: \.device.name)
            .values
            .compactMap { group in
                group.max { lhs, rhs in
                    let lhsConnected = lhs.device.level != nil
                    let rhsConnected = rhs.device.level != nil
                    if lhsConnected != rhsConnected { return !lhsConnected }
                    return lhs.sequence < rhs.sequence
                }?.device
            }
            .sorted { $0.name < $1.name }
    }
}

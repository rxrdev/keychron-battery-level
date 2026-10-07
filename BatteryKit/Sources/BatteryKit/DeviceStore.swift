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
        /// When this source last went from no level to a level; nil while disconnected
        var connectedSince: Int?
    }

    private var entries: [String: Entry] = [:]
    private var sequence = 0

    public init() {}

    /// An empty name keeps the stored one. A reading without a valid level for an
    /// id the store has never seen is ignored, so sources that never reported a
    /// battery leave no "Disconnected" rows behind.
    public mutating func apply(_ reading: BatteryReading) {
        let existing = entries[reading.id]
        let level = reading.level.flatMap { (0...100).contains($0) ? $0 : nil }
        guard existing != nil || level != nil,
              let name = reading.name.isEmpty ? existing?.device.name : reading.name else { return }

        sequence += 1
        let connectedSince = level == nil ? nil : (existing?.connectedSince ?? sequence)
        entries[reading.id] = Entry(
            device: Device(id: reading.id, name: name, level: level),
            sequence: sequence,
            connectedSince: connectedSince
        )
    }

    /// One device per name, sorted by name. The source that connected first keeps
    /// the slot while it stays connected; among disconnected ones the latest wins.
    public var visibleDevices: [Device] {
        Dictionary(grouping: entries.values, by: \.device.name)
            .values
            .compactMap { group in
                let connected = group.compactMap { entry in entry.connectedSince.map { (since: $0, device: entry.device) } }
                if let first = connected.min(by: { $0.since < $1.since }) {
                    return first.device
                }
                return group.max { $0.sequence < $1.sequence }?.device
            }
            .sorted { $0.name < $1.name }
    }
}

/// Reads a battery level from a Keychron raw HID input report. The format is a
/// heuristic (byte 0 is 0x02, byte 2 is the percentage), unconfirmed on hardware,
/// so reports are only trusted while a battery scan is waiting for an answer.
public enum HIDBatteryParser {
    public static func level(fromReport report: [UInt8], scanInProgress: Bool) -> Int? {
        guard scanInProgress, report.count >= 3, report[0] == 0x02, (1...100).contains(report[2]) else { return nil }
        return Int(report[2])
    }
}

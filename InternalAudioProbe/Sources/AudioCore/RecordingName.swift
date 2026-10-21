import Foundation

public enum RecordingName {
    /// Names use the recording's start time, the device's local time zone, and stable digits.
    public static func audioFile(startedAt: Date, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: startedAt)
        guard index > 0 else { return timestamp + ".m4a" }
        let number = String(index + 1)
        let suffix = number.count < 2 ? "0" + number : number
        return timestamp + "_" + suffix + ".m4a"
    }
}

import SwiftUI

func recordTimeText(_ date: Date, zone: String?) -> String {
    let formatter = DateFormatter(); formatter.locale = .autoupdatingCurrent; formatter.dateStyle = .medium; formatter.timeStyle = .short
    formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
    return formatter.string(from:date) + " · " + (zone ?? "归属时区未知，以当前时区显示")
}

struct AttributionZonePicker: View {
    @Binding var zone: String?
    var body: some View {
        Picker("归属时区", selection:$zone) {
            Text("未知").tag(String?.none)
            ForEach(TimeZone.knownTimeZoneIdentifiers, id:\.self) { Text($0).tag(Optional($0)) }
        }
    }
}

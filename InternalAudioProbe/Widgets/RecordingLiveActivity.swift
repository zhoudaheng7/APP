import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RecordingWidgets: WidgetBundle {
    var body: some Widget { RecordingLiveActivity() }
}

struct RecordingLiveActivity: Widget {
    private let aqua = Color(red: 0.25, green: 0.9, blue: 0.8)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "waveform").foregroundStyle(aqua)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.microphone ? "声屿 · 内部音＋麦克风" : "声屿 · 仅内部音").font(.headline)
                    Text(context.attributes.startedAt, style: .timer).monospacedDigit().font(.caption)
                    Text(context.state.message).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: StopRecordingIntent(sessionID: context.attributes.sessionID)) {
                    Label("停止并保存", systemImage: "stop.fill").font(.caption.weight(.semibold))
                }.tint(aqua)
            }.padding(16).activityBackgroundTint(Color(red: 0.035, green: 0.07, blue: 0.12))
                .activitySystemActionForegroundColor(aqua)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("声屿", systemImage: "waveform").foregroundStyle(aqua) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.startedAt, style: .timer).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.microphone ? "内部音＋麦克风" : "仅内部音").font(.caption)
                        Spacer()
                        Button(intent: StopRecordingIntent(sessionID: context.attributes.sessionID)) {
                            Label("停止并保存", systemImage: "stop.fill")
                        }.tint(aqua)
                    }.padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(aqua)
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(aqua)
            }.keylineTint(aqua)
        }
    }
}

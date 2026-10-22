#if os(iOS) && canImport(SwiftUI)
import Foundation
import SwiftUI

/// A presentation snapshot supplied by a caller, not a persistence or wire model.
public struct TodayDisplayItem: Identifiable, Equatable, Sendable {
    /// Presentation-only confidence; callers must supply it for every actual.
    public enum ActualStatus: Equatable, Sendable {
        case inferred
        case confirmed
        case rejected

        var label: String {
            switch self {
            case .inferred: "待确认"
            case .confirmed: "已确认"
            case .rejected: "已拒绝"
            }
        }
    }

    public enum Kind: Equatable, Sendable {
        case draftPlan
        case calendarCommitment
        case actualSession(ActualStatus)

        var label: String {
            switch self {
            case .draftPlan: "计划草稿"
            case .calendarCommitment: "日历承诺"
            case .actualSession: "实际记录"
            }
        }

        var symbolName: String {
            switch self {
            case .draftPlan: "pencil"
            case .calendarCommitment: "calendar"
            case .actualSession: "clock"
            }
        }

        var statusText: String {
            switch self {
            case .draftPlan: "草稿"
            case .calendarCommitment: "承诺记录"
            case .actualSession(let status): status.label
            }
        }

        var isActualSession: Bool {
            switch self {
            case .actualSession: true
            case .draftPlan, .calendarCommitment: false
            }
        }
    }

    public let id: UUID
    public let timeLabel: String
    public let title: String
    public let kind: Kind

    public init(id: UUID, timeLabel: String, title: String, kind: Kind) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.kind = kind
    }
}

/// A small render seam; it neither loads facts nor sends application commands.
@MainActor
public struct TodayChromePreview: View {
    private let items: [TodayDisplayItem]
    @State private var showsActualOnly = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [TodayDisplayItem]) {
        self.items = items
    }

    private var visibleItems: [TodayDisplayItem] {
        showsActualOnly ? items.filter { $0.kind.isActualSession } : items
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("今日时间线") {
                    if visibleItems.isEmpty {
                        Text(showsActualOnly ? "当前筛选下没有实际记录" : "今日暂无记录")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visibleItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.timeLabel).font(.caption)
                            Text(item.title).font(.body)
                            Label(item.kind.label, systemImage: item.kind.symbolName).font(.caption)
                            Text(item.kind.statusText).font(.caption)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .overlay {
                            rowBoundary(for: item.kind)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Today")
            .safeAreaInset(edge: .bottom) {
                filterControl
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    @ViewBuilder
    private func rowBoundary(for kind: TodayDisplayItem.Kind) -> some View {
        switch kind {
        case .draftPlan:
            Rectangle().strokeBorder(.primary, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        case .calendarCommitment:
            Rectangle().strokeBorder(.primary, lineWidth: 1)
        case .actualSession:
            RoundedRectangle(cornerRadius: 12).strokeBorder(.primary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var filterControl: some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased, !reduceMotion {
            LiquidGlassChrome26(showsActualOnly: showsActualOnly, onToggle: toggleFilter)
        } else {
            NativeChrome17(showsActualOnly: showsActualOnly, onToggle: toggleFilter)
        }
    }

    private func toggleFilter() {
        // Deliberately ephemeral: no repository, Calendar, or projection write.
        showsActualOnly.toggle()
    }
}

/// Both renderers use this identical button, text, accessibility, and hit target.
@MainActor
struct TodayFilterControl: View {
    let showsActualOnly: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        Button(action: onToggle) {
            Label(showsActualOnly ? "筛选：实际记录" : "筛选：全部", systemImage: "line.3.horizontal.decrease")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        }
        .accessibilityLabel("筛选今日时间线")
        .accessibilityValue(showsActualOnly ? "仅实际记录" : "全部记录")
        .accessibilityHint("在全部记录和仅实际记录之间切换")
        .accessibilityIdentifier("today.filter")
    }
}
#endif

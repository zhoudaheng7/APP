#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// The sole explicit glass surface is an interactive filter control.
@available(iOS 26, *)
@MainActor
public struct LiquidGlassChrome26: View {
    private let showsActualOnly: Bool
    private let onToggle: @MainActor () -> Void

    public init(showsActualOnly: Bool, onToggle: @escaping @MainActor () -> Void) {
        self.showsActualOnly = showsActualOnly
        self.onToggle = onToggle
    }

    public var body: some View {
        TodayFilterControl(showsActualOnly: showsActualOnly, onToggle: onToggle)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
    }
}
#endif

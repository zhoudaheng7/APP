#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// Baseline and accessibility fallback: one opaque, outlined system button.
@MainActor
public struct NativeChrome17: View {
    private let showsActualOnly: Bool
    private let onToggle: @MainActor () -> Void

    public init(showsActualOnly: Bool, onToggle: @escaping @MainActor () -> Void) {
        self.showsActualOnly = showsActualOnly
        self.onToggle = onToggle
    }

    public var body: some View {
        TodayFilterControl(showsActualOnly: showsActualOnly, onToggle: onToggle)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.primary, lineWidth: 1).allowsHitTesting(false)
            }
    }
}
#endif

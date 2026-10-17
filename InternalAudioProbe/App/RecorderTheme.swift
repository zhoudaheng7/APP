import SwiftUI

// Midnight navy and quiet aqua, matching the existing app icon. No scrolling blur/shadow passes.
enum RecorderTheme {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.075)
    static let surface = Color(red: 0.055, green: 0.085, blue: 0.12)
    static let accent = Color(red: 0.20, green: 0.88, blue: 0.77)
    static let blue = Color(red: 0.17, green: 0.67, blue: 0.79)
    static let border = accent.opacity(0.11)
}

struct RecorderCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(12)
            .background(RecorderTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RecorderTheme.border, lineWidth: 0.5))
    }
}

extension View {
    func recorderCard() -> some View { modifier(RecorderCardStyle()) }
    func recorderRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

import SwiftUI

enum PosColors {
    static let cream = Color(red: 250 / 255, green: 243 / 255, blue: 223 / 255)
    static let burgundy = Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255)
    static let teal = Color(red: 0 / 255, green: 109 / 255, blue: 119 / 255)
    static let numpadKey = Color(red: 168 / 255, green: 213 / 255, blue: 209 / 255)
    /// Content cards (denom rows, status strip) — Android `PosHighlightPanel`.
    static let highlightPanel = numpadKey.opacity(0.25)
    static let panelBorder = Color.black.opacity(0.75)
}

extension View {
    func posPanelStyle() -> some View {
        padding(10)
            .background(Color.white.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(PosColors.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Android `OutlinedButton` for payment quick amounts (exact due + bill shortcuts).
struct PosOutlinedQuickButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PosColors.burgundy, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

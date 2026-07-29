import CoreGraphics
import SwiftUI

/// Layout constants aligned with Android `PosLayoutMetrics.kt`.
enum PosLayoutMetrics {
    /// Max width for a standard number pad (no till nav column).
    static let numpadColumnWidth: CGFloat = 270
    /// Fixed height for every number-pad host.
    static let numpadCardHeight: CGFloat = 222
    static let numpadKeyGap: CGFloat = 6
    static let numpadInnerPadding: CGFloat = 9
    /// Up/down denomination keys beside till-count numpad.
    static let numpadNavKeyWidth: CGFloat = 40
    /// Max width for till numpad including nav arrow column.
    static let tillNumpadCardWidth: CGFloat = numpadColumnWidth + numpadNavKeyWidth + numpadKeyGap

    static let registerSideGutter: CGFloat = 16
    static let registerCenterGutter: CGFloat = 12

    /// Space above/below numpad inside till-count panel (Android `TillPanelEdgeSpacer`).
    static let tillPanelEdgeSpacer: CGFloat = 12
    static let tillPanelGutter: CGFloat = 8
    static let tillDenomPanelWeight: CGFloat = 0.63
    static let tillGutterWeight: CGFloat = 0.02
    static let tillNumpadPanelWeight: CGFloat = 0.35

    /// Denomination row sizing — 5% shorter than prior values; padding moved to status bar.
    static let tillDenomRowVerticalPadding: CGFloat = 9.5
    static let tillDenomRowSpacing: CGFloat = 4
    static let tillDenomRowMinHeight: CGFloat = 43.7

    /// Selected / action status strip.
    static let tillStatusBarVerticalPadding: CGFloat = 14
    static let tillStatusBarMinHeight: CGFloat = 56
}

extension View {
    /// Standard host size for a number pad: fixed height, width capped at the shared max.
    func numberPadHostSize(withNavColumn: Bool = false) -> some View {
        let maxWidth = withNavColumn
            ? PosLayoutMetrics.tillNumpadCardWidth
            : PosLayoutMetrics.numpadColumnWidth
        return self
            .frame(maxWidth: maxWidth)
            .frame(height: PosLayoutMetrics.numpadCardHeight)
    }
}

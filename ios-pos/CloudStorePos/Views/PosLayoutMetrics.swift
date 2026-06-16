import CoreGraphics

/// Layout constants aligned with Android `PosLayoutMetrics.kt`.
enum PosLayoutMetrics {
    static let numpadColumnWidth: CGFloat = 280
    static let numpadCardHeight: CGFloat = 222
    static let numpadKeyHeight: CGFloat = 48
    static let numpadKeyGap: CGFloat = 6
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

    static let numpadInnerPadding: CGFloat = 9
}

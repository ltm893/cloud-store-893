import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let listerPrimary = Color(hex: 0x872434)
    static let listerAccent = Color(hex: 0x114B5F)
    static let listerBackground = Color(hex: 0xFAF3DF)
    static let listerHighlight = Color(hex: 0xD0E4EB)
}

extension View {
    func listerNavigationBar() -> some View {
        toolbarBackground(Color.listerPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

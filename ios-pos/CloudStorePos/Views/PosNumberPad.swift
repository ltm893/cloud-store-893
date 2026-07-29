import SwiftUI

struct PosNumberPad: View {
    let onDigit: (Character) -> Void
    let onClear: () -> Void
    let onBackspace: () -> Void
    let onDecimal: (() -> Void)?
    let onUp: (() -> Void)?
    let onDown: (() -> Void)?

    init(
        onDigit: @escaping (Character) -> Void,
        onClear: @escaping () -> Void,
        onBackspace: @escaping () -> Void,
        onDecimal: (() -> Void)? = nil,
        onUp: (() -> Void)? = nil,
        onDown: (() -> Void)? = nil
    ) {
        self.onDigit = onDigit
        self.onClear = onClear
        self.onBackspace = onBackspace
        self.onDecimal = onDecimal
        self.onUp = onUp
        self.onDown = onDown
    }

    private let keyRows = ["123", "456", "789"]
    private var keyGap: CGFloat { PosLayoutMetrics.numpadKeyGap }

    var body: some View {
        HStack(spacing: keyGap) {
            VStack(spacing: keyGap) {
                ForEach(keyRows, id: \.self) { row in
                    keyRow {
                        ForEach(Array(row), id: \.self) { ch in
                            padKey(String(ch)) { onDigit(ch) }
                        }
                    }
                }
                keyRow {
                    if let onDecimal {
                        padKey(".", action: onDecimal)
                    } else {
                        padKey("C", action: onClear)
                    }
                    padKey("0") { onDigit("0") }
                    padKey("⌫", action: onBackspace)
                }
            }

            if let onUp, let onDown {
                VStack(spacing: keyGap) {
                    navKey("↑", action: onUp)
                    navKey("↓", action: onDown)
                }
                .frame(width: PosLayoutMetrics.numpadNavKeyWidth)
            }
        }
    }

    @ViewBuilder
    private func keyRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: keyGap) {
            content()
        }
        .frame(maxHeight: .infinity)
    }

    private func padKey(
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PosColors.numpadKey)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func navKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PosColors.numpadKey)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

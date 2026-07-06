import SwiftUI

struct ProductFieldRow: View {
    let label: String
    let value: String
    var valueFont: Font = .subheadline

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(valueFont)
                .multilineTextAlignment(.trailing)
        }
    }
}

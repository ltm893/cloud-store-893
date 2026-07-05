import SwiftUI

struct NumericKeypadGrid: View {
    @Binding var inputText: String
    var submitLabel: String = "Lookup"
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            ForEach(0..<3) { row in
                HStack(spacing: 15) {
                    ForEach(1..<4) { col in
                        let number = row * 3 + col
                        numKey("\(number)") { inputText += "\(number)" }
                    }
                }
            }

            HStack(spacing: 15) {
                Button {
                    if !inputText.isEmpty { inputText.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title)
                        .frame(width: 80, height: 80)
                        .background(Color.listerHighlight)
                        .foregroundColor(Color.listerAccent)
                        .cornerRadius(40)
                }

                numKey("0") { inputText += "0" }

                Button { inputText = "" } label: {
                    Text("C")
                        .font(.title)
                        .frame(width: 80, height: 80)
                        .background(Color.listerHighlight)
                        .foregroundColor(Color.listerAccent)
                        .cornerRadius(40)
                }
            }

            Button(action: onSubmit) {
                Text(submitLabel)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(Color.listerAccent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func numKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title)
                .frame(width: 80, height: 80)
                .background(Color.listerHighlight)
                .foregroundColor(Color.listerAccent)
                .cornerRadius(40)
        }
    }
}

import SwiftUI

private let tillPanelBorder = Color.black.opacity(0.75)
private let tillSideGutter: CGFloat = 20
private let tillCenterGutter: CGFloat = 28

struct OpeningTillScreen: View {
    let expectedOpeningFloat: Double?
    let denominations: [TillDenomination]
    let counts: [String: String]
    let selectedDenominationId: String?
    let status: String
    let submitting: Bool
    let onSelectDenomination: (String) -> Void
    let onDigit: (Character) -> Void
    let onClearCount: () -> Void
    let onBackspaceCount: () -> Void
    let onPreviousDenomination: () -> Void
    let onNextDenomination: () -> Void
    let onSubmit: () -> Void
    let onNoCashToday: () -> Void
    let onCancel: () -> Void

    private var countedTotal: Double {
        TillCountLogic.sumTillCounts(denominations: denominations, counts: counts)
    }

    private var canSubmit: Bool {
        TillCountLogic.canSubmit(
            expectedOpeningFloat: expectedOpeningFloat,
            denominations: denominations,
            counts: counts
        )
    }

    private var selected: TillDenomination? {
        denominations.first { $0.id == selectedDenominationId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            mainPanels
            statusBar
            actionButtons
        }
        .background(Color(red: 250 / 255, green: 243 / 255, blue: 223 / 255))
    }

    private var mainPanels: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: tillSideGutter)

            denominationList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tillPanelStyle()

            Spacer(minLength: tillCenterGutter)

            PosNumberPad(
                onDigit: onDigit,
                onClear: onClearCount,
                onBackspace: onBackspaceCount,
                onUp: onPreviousDenomination,
                onDown: onNextDenomination
            )
            .frame(maxWidth: 280)
            .frame(maxHeight: .infinity)
            .tillPanelStyle()

            Spacer(minLength: tillSideGutter)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Count opening till")
                .font(.title3.bold())
            Text(TillCountLogic.summaryLine(
                expectedOpeningFloat: expectedOpeningFloat,
                countedTotal: countedTotal
            ))
            .font(.subheadline)
            Text("Tap row → count · ↑↓ to move")
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(Color(red: 250 / 255, green: 243 / 255, blue: 223 / 255))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
        }
    }

    private var denominationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(denominations) { denom in
                        let count = Int(counts[denom.id] ?? "") ?? 0
                        let isSelected = denom.id == selectedDenominationId
                        Button {
                            onSelectDenomination(denom.id)
                        } label: {
                            HStack {
                                Text(denom.label)
                                    .fontWeight(isSelected ? .bold : .medium)
                                Spacer()
                                Text(count > 0 ? "× \(count)" : "—")
                                    .fontWeight(.bold)
                                    .foregroundStyle(isSelected ? Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255) : .primary)
                                Text(TillCountLogic.formatMoney(denom.value * Double(count)))
                                    .font(.caption)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isSelected
                                            ? Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255)
                                            : tillPanelBorder.opacity(0.45),
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .id(denom.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedDenominationId) { _, newId in
                guard let newId else { return }
                withAnimation {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(selectionStatus)
                .font(.caption)
                .fontWeight(.semibold)
            Spacer()
            Text(TillCountLogic.actionStatus(
                expectedOpeningFloat: expectedOpeningFloat,
                denominations: denominations,
                counts: counts,
                submitting: submitting,
                status: status
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tillPanelBorder.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, tillSideGutter)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, tillSideGutter)
        }
    }

    private var selectionStatus: String {
        guard let selected else { return "Select a denomination" }
        let countText = counts[selected.id] ?? ""
        let count = Int(countText) ?? 0
        let displayCount = countText.isEmpty ? "0" : countText
        return "Selected: \(selected.label) · \(displayCount) · \(TillCountLogic.formatMoney(selected.value * Double(count)))"
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(submitting ? "Submitting…" : "Submit Till Count") {
                onSubmit()
            }
            .buttonStyle(PosPrimaryButtonStyle())
            .disabled(submitting || !canSubmit)

            Button("Credit Cards Only") {
                onNoCashToday()
            }
            .buttonStyle(PosPrimaryButtonStyle())
            .disabled(submitting)

            Button("Cancel") {
                onCancel()
            }
            .font(.headline)
            .foregroundStyle(Color(red: 135 / 255, green: 36 / 255, blue: 52 / 255))
            .disabled(submitting)
        }
        .padding(.horizontal, tillSideGutter)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, tillSideGutter)
        }
    }
}

private extension View {
    func tillPanelStyle() -> some View {
        padding(10)
            .background(Color.white.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tillPanelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

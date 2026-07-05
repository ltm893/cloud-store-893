import SwiftUI

private let tillPanelBorder = Color.black.opacity(0.75)

struct TillCountScreenOptions {
    var screenTitle = "Count opening till"
    var referenceLabel = "Target"
    var headerHint = "Tap row -> count · ↑↓ to move"
    var submitButtonText = "Submit Till Count"
    var showNoCashButton = true
    var requireExactMatch = true
    var supervisorApprovalRequired = true
    var defaultStatus = "Count opening till"
    var secondaryHeaderLine: String?

    static let opening = TillCountScreenOptions()

    static func closing(headerHint: String?, supervisorApprovalRequired: Bool) -> TillCountScreenOptions {
        TillCountScreenOptions(
            screenTitle: "Close till",
            referenceLabel: "Expected",
            headerHint: "Tap row -> count · ↑↓ to move",
            submitButtonText: supervisorApprovalRequired ? "Submit for approval" : "Close till",
            showNoCashButton: false,
            requireExactMatch: false,
            supervisorApprovalRequired: supervisorApprovalRequired,
            defaultStatus: "Count closing till",
            secondaryHeaderLine: headerHint
        )
    }
}

struct OpeningTillScreen: View {
    let expectedOpeningFloat: Double?
    let denominations: [TillDenomination]
    let counts: [String: String]
    let selectedDenominationId: String?
    let status: String
    let submitting: Bool
    let options: TillCountScreenOptions
    let onSelectDenomination: (String) -> Void
    let onDigit: (Character) -> Void
    let onClearCount: () -> Void
    let onBackspaceCount: () -> Void
    let onPreviousDenomination: () -> Void
    let onNextDenomination: () -> Void
    let onSubmit: () -> Void
    let onNoCashToday: () -> Void
    let onCancel: () -> Void

    init(
        expectedOpeningFloat: Double?,
        denominations: [TillDenomination],
        counts: [String: String],
        selectedDenominationId: String?,
        status: String,
        submitting: Bool,
        options: TillCountScreenOptions = .opening,
        onSelectDenomination: @escaping (String) -> Void,
        onDigit: @escaping (Character) -> Void,
        onClearCount: @escaping () -> Void,
        onBackspaceCount: @escaping () -> Void,
        onPreviousDenomination: @escaping () -> Void,
        onNextDenomination: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        onNoCashToday: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.expectedOpeningFloat = expectedOpeningFloat
        self.denominations = denominations
        self.counts = counts
        self.selectedDenominationId = selectedDenominationId
        self.status = status
        self.submitting = submitting
        self.options = options
        self.onSelectDenomination = onSelectDenomination
        self.onDigit = onDigit
        self.onClearCount = onClearCount
        self.onBackspaceCount = onBackspaceCount
        self.onPreviousDenomination = onPreviousDenomination
        self.onNextDenomination = onNextDenomination
        self.onSubmit = onSubmit
        self.onNoCashToday = onNoCashToday
        self.onCancel = onCancel
    }

    private var countedTotal: Double {
        TillCountLogic.sumTillCounts(denominations: denominations, counts: counts)
    }

    private var canSubmit: Bool {
        TillCountLogic.canSubmit(
            expectedOpeningFloat: expectedOpeningFloat,
            denominations: denominations,
            counts: counts,
            requireExactMatch: options.requireExactMatch
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
        .background(PosColors.cream)
    }

    private var mainPanels: some View {
        GeometryReader { geo in
            let sidePad = PosLayoutMetrics.tillPanelGutter
            let contentWidth = max(0, geo.size.width - sidePad * 2)
            HStack(spacing: 0) {
                Spacer().frame(width: sidePad)
                denominationPanel
                    .frame(width: contentWidth * PosLayoutMetrics.tillDenomPanelWeight)
                Spacer().frame(width: contentWidth * PosLayoutMetrics.tillGutterWeight)
                numpadPanel
                    .frame(width: contentWidth * PosLayoutMetrics.tillNumpadPanelWeight)
                Spacer().frame(width: sidePad)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxHeight: .infinity)
    }

    private var denominationPanel: some View {
        denominationList
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(4)
    }

    private var numpadPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: PosLayoutMetrics.tillPanelEdgeSpacer)
            PosNumberPad(
                layout: .compact,
                onDigit: onDigit,
                onClear: onClearCount,
                onBackspace: onBackspaceCount,
                onUp: onPreviousDenomination,
                onDown: onNextDenomination
            )
            .padding(PosLayoutMetrics.numpadInnerPadding)
            .frame(height: PosLayoutMetrics.numpadCardHeight)
            Spacer(minLength: PosLayoutMetrics.tillPanelEdgeSpacer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PosColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(options.screenTitle)
                .font(.title3.bold())
            Text(TillCountLogic.summaryLine(
                expectedOpeningFloat: expectedOpeningFloat,
                countedTotal: countedTotal,
                referenceLabel: options.referenceLabel
            ))
            .font(.subheadline)
            if let secondaryHeaderLine = options.secondaryHeaderLine, !secondaryHeaderLine.isEmpty {
                Text(secondaryHeaderLine)
                    .font(.caption)
                    .opacity(0.9)
            }
            Text(options.headerHint)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(PosColors.cream)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PosColors.burgundy)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
        }
    }

    private var denominationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: PosLayoutMetrics.tillDenomRowSpacing) {
                    ForEach(denominations) { denom in
                        denominationRow(denom)
                            .id(denom.id)
                    }
                }
            }
            .onChange(of: selectedDenominationId) { _, newId in
                guard let newId else { return }
                withAnimation {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }

    private func denominationRow(_ denom: TillDenomination) -> some View {
        let count = Int(counts[denom.id] ?? "") ?? 0
        let isSelected = denom.id == selectedDenominationId
        return Button {
            onSelectDenomination(denom.id)
        } label: {
            HStack {
                Text(denom.label)
                    .font(.body)
                    .fontWeight(isSelected ? .bold : .medium)
                Spacer()
                Text(count > 0 ? "× \(count)" : "—")
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? PosColors.burgundy : .primary)
                    .padding(.horizontal, 4)
                Text(TillCountLogic.formatMoney(denom.value * Double(count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(minHeight: PosLayoutMetrics.tillDenomRowMinHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, PosLayoutMetrics.tillDenomRowVerticalPadding)
            .background(PosColors.highlightPanel)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PosColors.burgundy, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var statusBar: some View {
        HStack {
            Text(selectionStatus)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(TillCountLogic.actionStatus(
                expectedOpeningFloat: expectedOpeningFloat,
                denominations: denominations,
                counts: counts,
                submitting: submitting,
                status: status,
                defaultStatus: options.defaultStatus,
                requireExactMatch: options.requireExactMatch,
                supervisorApprovalRequired: options.supervisorApprovalRequired
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, PosLayoutMetrics.tillStatusBarVerticalPadding)
        .frame(minHeight: PosLayoutMetrics.tillStatusBarMinHeight)
        .background(PosColors.highlightPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tillPanelBorder.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, PosLayoutMetrics.tillPanelGutter)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, PosLayoutMetrics.tillPanelGutter)
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
            Button(submitting ? "Submitting…" : options.submitButtonText) {
                onSubmit()
            }
            .buttonStyle(PosTealButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(submitting || !canSubmit)

            if options.showNoCashButton {
                Button("Credit Cards Only") {
                    onNoCashToday()
                }
                .buttonStyle(PosTealButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(submitting)
            }

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(PosBurgundyButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(submitting)
        }
        .padding(.horizontal, PosLayoutMetrics.tillPanelGutter)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, PosLayoutMetrics.tillPanelGutter)
        }
    }
}

struct PosTealButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(PosColors.teal)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PosBurgundyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(PosColors.burgundy)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

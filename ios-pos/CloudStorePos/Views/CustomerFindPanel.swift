import SwiftUI

struct CustomerFindPanel: View {
    let customers: [StoreCustomer]
    let linkedCustomerId: Int?
    let onLink: (Int) -> Void
    let onUnlink: () -> Void
    let onClose: () -> Void

    @State private var query = ""

    private var matches: [StoreCustomer] {
        CustomerFindLogic.filterMatches(customers: customers, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Find customer")
                    .font(.subheadline.bold())
                    .foregroundStyle(PosColors.burgundy)
                Spacer()
                Button("Keypad", action: onClose)
                    .font(.footnote.bold())
                    .foregroundStyle(PosColors.burgundy)
                    .buttonStyle(.plain)
            }

            TextField("Id or Name", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let linkedCustomerId {
                let linked = customers.first { $0.id == linkedCustomerId }
                Text("Linked: \(CustomerFindLogic.displayName(linked, customerId: linkedCustomerId))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Unlink customer", action: onUnlink)
                    .font(.caption.bold())
                    .foregroundStyle(PosColors.burgundy)
                    .buttonStyle(.plain)
            }

            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Color.clear
                } else if matches.isEmpty {
                    Text("No customers found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(matches) { customer in
                                Button {
                                    onLink(customer.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(CustomerFindLogic.displayName(customer, customerId: customer.id))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        let detail = [customer.email, customer.phone]
                                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · ")
                                        if !detail.isEmpty {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(PosOutlinedQuickButtonStyle())
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

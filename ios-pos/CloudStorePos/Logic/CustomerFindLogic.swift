import Foundation

enum CustomerFindLogic {
    static func displayName(_ customer: StoreCustomer?, customerId: Int) -> String {
        customer?.name ?? "Customer #\(customerId)"
    }

    static func filterMatches(
        customers: [StoreCustomer],
        query: String,
        limit: Int = 12
    ) -> [StoreCustomer] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let asId = Int(trimmed)
        let matches = customers.filter { customer in
            if let asId {
                return customer.id == asId || String(customer.id).hasPrefix(trimmed)
            }
            let nameMatch = customer.name.localizedCaseInsensitiveContains(trimmed)
            let emailMatch = customer.email?.localizedCaseInsensitiveContains(trimmed) ?? false
            let phoneMatch = customer.phone?.localizedCaseInsensitiveContains(trimmed) ?? false
            return nameMatch || emailMatch || phoneMatch
        }
        return Array(matches.prefix(limit))
    }
}

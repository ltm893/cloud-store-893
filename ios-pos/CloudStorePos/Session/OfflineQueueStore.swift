import Foundation

struct PendingCheckout: Codable, Equatable {
    let paymentMethod: String
    let payments: [CheckoutPayment]?
    let checkoutTotal: Double?
    let customerId: Int?
    let createdAtMs: Int64
    let cartLines: [CartLineQuantity]
}

final class OfflineQueueStore {
    static let shared = OfflineQueueStore()

    private let defaultsKey = "pending_checkouts"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: "pos_offline_queue") ?? .standard) {
        self.defaults = defaults
    }

    func all() -> [PendingCheckout] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingCheckout].self, from: data)) ?? []
    }

    func enqueue(
        paymentMethod: String,
        customerId: Int?,
        cartLines: [CartLineQuantity],
        payments: [CheckoutPayment]? = nil,
        checkoutTotal: Double? = nil
    ) {
        var current = all()
        current.append(
            PendingCheckout(
                paymentMethod: paymentMethod,
                payments: payments,
                checkoutTotal: checkoutTotal,
                customerId: customerId,
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                cartLines: cartLines
            )
        )
        save(current)
    }

    func replace(_ items: [PendingCheckout]) {
        save(items)
    }

    func clear() {
        save([])
    }

    private func save(_ items: [PendingCheckout]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

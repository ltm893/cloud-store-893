import XCTest
@testable import CloudStorePos

final class OfflineQueueStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "OfflineQueueStoreTests")!
        defaults.removePersistentDomain(forName: "OfflineQueueStoreTests")
    }

    func testEnqueueAndReplaceRoundTrip() {
        let store = OfflineQueueStore(defaults: defaults)
        XCTAssertTrue(store.all().isEmpty)

        store.enqueue(
            paymentMethod: "cash",
            customerId: 42,
            cartLines: [CartLineQuantity(productId: 1, quantity: 2)],
            payments: [CheckoutPayment(method: "cash", amount: 10, tenderedAmount: 20, changeGiven: 10)],
            checkoutTotal: 10
        )

        let queued = store.all()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued[0].paymentMethod, "cash")
        XCTAssertEqual(queued[0].customerId, 42)
        XCTAssertEqual(queued[0].cartLines, [CartLineQuantity(productId: 1, quantity: 2)])
        XCTAssertEqual(queued[0].payments?.count, 1)
        XCTAssertEqual(queued[0].checkoutTotal, 10)
        XCTAssertGreaterThan(queued[0].createdAtMs, 0)

        store.replace([])
        XCTAssertTrue(store.all().isEmpty)
    }

    func testClearRemovesAllEntries() {
        let store = OfflineQueueStore(defaults: defaults)
        store.enqueue(paymentMethod: "card", customerId: nil, cartLines: [CartLineQuantity(productId: 5, quantity: 1)])
        store.clear()
        XCTAssertTrue(store.all().isEmpty)
    }
}

final class OfflineQueueFlushLogicTests: XCTestCase {
    func testBuildStatusMessageCombinesParts() {
        let message = OfflineQueueFlushLogic.buildStatusMessage(
            .init(synced: 2, droppedStale: 1, droppedPermanent: 0, remaining: 1, lastError: "HTTP 500")
        )
        XCTAssertEqual(
            message,
            "Synced 2 sale(s) · dropped 1 old entries (no cart saved) · 1 still pending: HTTP 500"
        )
    }

    func testBuildStatusMessageWhenEmpty() {
        XCTAssertEqual(
            OfflineQueueFlushLogic.buildStatusMessage(
                .init(synced: 0, droppedStale: 0, droppedPermanent: 0, remaining: 0, lastError: nil)
            ),
            "Nothing to sync"
        )
    }
}

final class NetworkErrorLogicTests: XCTestCase {
    func testOfflineURLErrorIsOfflineLike() {
        XCTAssertTrue(NetworkErrorLogic.isOfflineLike(URLError(.notConnectedToInternet)))
        XCTAssertTrue(NetworkErrorLogic.isOfflineLike(URLError(.timedOut)))
    }

    func testHttpErrorIsNotOfflineLike() {
        XCTAssertFalse(NetworkErrorLogic.isOfflineLike(PosAPIError.httpStatus(500, "fail")))
    }
}

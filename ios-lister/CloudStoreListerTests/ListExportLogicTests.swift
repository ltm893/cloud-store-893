import XCTest
@testable import CloudStoreLister

final class ListExportLogicTests: XCTestCase {
    private func sampleItem(
        productId: Int = 1,
        name: String = "Test Product",
        productType: String? = "Coffee",
        barcode: String? = "123456",
        priceLabel: String = "$9.99",
        stockLabel: String = "12 in stock",
        pullCount: Int = 2
    ) -> InventoryListItem {
        InventoryListItem(
            productId: productId,
            barcode: barcode,
            name: name,
            productType: productType,
            manufacturer: nil,
            priceLabel: priceLabel,
            stockLabel: stockLabel,
            stockEmphasis: false,
            pullCount: pullCount
        )
    }

    func testSummaryCountsItemsAndPullTotals() {
        let items = [
            sampleItem(pullCount: 2),
            sampleItem(productId: 2, pullCount: 4),
            sampleItem(productId: 3, pullCount: 1),
        ]
        let summary = ListExportLogic.summary(for: items)
        XCTAssertEqual(summary.itemCount, 3)
        XCTAssertEqual(summary.totalPullCount, 7)
    }

    func testSummaryEmptyList() {
        let summary = ListExportLogic.summary(for: [])
        XCTAssertEqual(summary.itemCount, 0)
        XCTAssertEqual(summary.totalPullCount, 0)
    }

    func testCSVHeader() {
        let csv = ListExportLogic.buildCSVString(for: [])
        XCTAssertTrue(csv.hasPrefix("Name,Type,Product ID,Barcode,Price,Stock,Pull Count\n"))
    }

    func testCSVDataRow() {
        let csv = ListExportLogic.buildCSVString(for: [
            sampleItem(productId: 42, name: "Whiskey", productType: "Spirits", pullCount: 3),
        ])
        XCTAssertTrue(csv.contains("\"Whiskey\""))
        XCTAssertTrue(csv.contains("\"Spirits\""))
        XCTAssertTrue(csv.contains("\"42\""))
        XCTAssertTrue(csv.contains(",3\n"))
    }

    func testCSVQuotesNameWithComma() {
        let csv = ListExportLogic.buildCSVString(for: [
            sampleItem(name: "Big, Bold Bourbon"),
        ])
        XCTAssertTrue(csv.contains("\"Big, Bold Bourbon\""))
    }

    func testWriteCSVFileUsesSanitizedListName() throws {
        let url = try XCTUnwrap(
            ListExportLogic.writeCSVFile(
                items: [sampleItem()],
                listName: "My Pull List"
            )
        )
        XCTAssertTrue(url.lastPathComponent.hasPrefix("My_Pull_List_"))
        XCTAssertEqual(url.pathExtension, "csv")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"Test Product\""))
    }
}

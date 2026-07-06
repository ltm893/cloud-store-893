import XCTest
@testable import CloudStoreLister

final class CSVImportLogicTests: XCTestCase {
    func testParseCSVWithHeader() {
        let csv = """
        Name,Product ID,Pull Count
        Widget,42,2
        Gadget,7,1
        """
        let parsed = CSVImportLogic.parseCSV(csv)!
        XCTAssertEqual(parsed.headers, ["Name", "Product ID", "Pull Count"])
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0][1], "42")
    }

    func testParseCSVLineHandlesQuotedCommas() {
        let fields = CSVImportLogic.parseCSVLine("\"Big, Bold\",123")
        XCTAssertEqual(fields, ["Big, Bold", "123"])
    }

    func testSuggestedMappingFindsProductIdAndOptionalFields() {
        let csv = """
        Name,Product ID,Barcode,Pull Count
        Widget,42,999,2
        """
        let parsed = CSVImportLogic.parseCSV(csv)!
        let mapping = CSVImportLogic.suggestedMapping(for: parsed)
        XCTAssertEqual(mapping.productIdColumn, "Product ID")
        XCTAssertTrue(mapping.enabledFields.contains(.name))
        XCTAssertTrue(mapping.enabledFields.contains(.barcode))
        XCTAssertTrue(mapping.enabledFields.contains(.pullCount))
    }

    func testBuildItemsUsesMappedColumns() throws {
        let csv = """
        Name,Product ID,Pull Count
        Widget,42,3
        """
        let parsed = CSVImportLogic.parseCSV(csv)!
        var mapping = CSVImportLogic.suggestedMapping(for: parsed)
        mapping.productIdColumn = "Product ID"
        mapping.enabledFields = [.name, .pullCount]
        mapping.columnByField = [.name: "Name", .pullCount: "Pull Count"]

        let items = try CSVImportLogic.buildItems(parsed: parsed, mapping: mapping)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].productId, 42)
        XCTAssertEqual(items[0].name, "Widget")
        XCTAssertEqual(items[0].pullCount, 3)
        XCTAssertEqual(items[0].priceLabel, "—")
    }

    func testBuildItemsRequiresProductIdColumn() {
        let parsed = ParsedCSV(headers: ["Name"], rows: [["Widget"]])
        let mapping = CSVFieldMapping()
        XCTAssertThrowsError(try CSVImportLogic.buildItems(parsed: parsed, mapping: mapping)) { error in
            XCTAssertEqual(error as? CSVImportError, .missingProductIdColumn)
        }
    }

    func testApplyImportIncrementsDuplicatePullCount() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        let item = InventoryListItem(
            productId: 42,
            barcode: nil,
            name: "Widget",
            productType: nil,
            manufacturer: nil,
            priceLabel: "$1.00",
            stockLabel: "5",
            stockEmphasis: false,
            pullCount: 2
        )
        lists = CSVImportLogic.applyImport(items: [item, item], toListId: InventoryListDefaults.myListId, in: lists)
        XCTAssertEqual(lists[0].items.count, 1)
        XCTAssertEqual(lists[0].items[0].pullCount, 3)
    }
}

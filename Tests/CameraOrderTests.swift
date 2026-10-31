import Foundation
import LogBatchCore
import XCTest

final class CameraOrderTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testDefaultOrderAndRepeatedPromotionsPreserveOtherProducts() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = CameraOrderStore(defaults: defaults)
        let products = try LUTCatalog.load().products
        let initial = store.orderedProducts(products).map(\.id)
        XCTAssertEqual(Array(initial.prefix(3)), ["nano", "osmo-pocket-4p", "osmo-pocket-4"])
        XCTAssertTrue(store.moveToFront("osmo-pocket-4", among: products))
        XCTAssertEqual(store.orderedProducts(products).map(\.id), ["osmo-pocket-4"] + initial.filter { $0 != "osmo-pocket-4" })
        XCTAssertTrue(store.moveToFront("osmo-pocket-4p", among: products))
        let expected = ["osmo-pocket-4p", "osmo-pocket-4"] + initial.filter { !["osmo-pocket-4p", "osmo-pocket-4"].contains($0) }
        XCTAssertEqual(store.orderedProducts(products).map(\.id), expected)
        XCTAssertFalse(store.moveToFront("osmo-pocket-4p", among: products))
        XCTAssertFalse(store.moveToFront("unknown", among: products))
        XCTAssertEqual(store.orderedProducts(products).map(\.id), expected)
    }

    @MainActor
    func testPromotionsSurviveAStoreReload() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let products = try LUTCatalog.load().products
        let first = CameraOrderStore(defaults: defaults)
        first.moveToFront("mini-5-pro", among: products)
        first.moveToFront("osmo-pocket-3", among: products)
        let reloaded = CameraOrderStore(defaults: defaults)
        XCTAssertEqual(reloaded.orderedProducts(products), first.orderedProducts(products))
    }

    @MainActor
    func testFilteredFirstProductCannotBePromotedButOthersUpdateTheGlobalOrder() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let products = try LUTCatalog.load().products
        let filtered = products.filter { ["osmo-action-6", "mini-5-pro", "air-3s"].contains($0.id) }
        let store = CameraOrderStore(defaults: defaults)
        XCTAssertEqual(store.orderedProducts(filtered).first?.id, "osmo-action-6")
        XCTAssertFalse(store.moveToFront("osmo-action-6", among: filtered))
        XCTAssertTrue(store.moveToFront("mini-5-pro", among: filtered))
        XCTAssertEqual(store.orderedProducts(filtered).first?.id, "mini-5-pro")
        XCTAssertEqual(store.orderedProducts(products).first?.id, "mini-5-pro")
        XCTAssertFalse(store.moveToFront("nano", among: filtered))
    }

    @MainActor
    func testDuplicateAndUnknownSavedIDsDoNotDuplicateOrHideProducts() throws {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["unknown", "osmo-pocket-4", "osmo-pocket-4", "nano"], forKey: CameraOrderStore.preferenceKey)
        let products = try LUTCatalog.load().products
        let ordered = CameraOrderStore(defaults: defaults).orderedProducts(products)
        XCTAssertEqual(ordered.first?.id, "osmo-pocket-4")
        XCTAssertEqual(ordered.count, products.count)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(products.map(\.id)))
        defaults.set(42, forKey: CameraOrderStore.preferenceKey)
        XCTAssertEqual(CameraOrderStore(defaults: defaults).orderedProducts(products).first?.id, "nano")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let domain = "LogBatchTests.CameraOrder." + UUID().uuidString
        return (UserDefaults(suiteName: domain)!, domain)
    }
}

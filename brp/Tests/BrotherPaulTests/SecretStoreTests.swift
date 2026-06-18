import XCTest
@testable import BrotherPaul

final class SecretStoreTests: XCTestCase {

    func testInMemoryStoreRoundTrips() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get(SecretKey.anthropicAPIKey))
        store.set("sk-ant-123", for: SecretKey.anthropicAPIKey)
        XCTAssertEqual(store.get(SecretKey.anthropicAPIKey), "sk-ant-123")
        store.delete(SecretKey.anthropicAPIKey)
        XCTAssertNil(store.get(SecretKey.anthropicAPIKey))
    }

    func testInMemoryStoreOverwrites() {
        let store = InMemorySecretStore()
        store.set("a", for: "k")
        store.set("b", for: "k")
        XCTAssertEqual(store.get("k"), "b")
    }
}

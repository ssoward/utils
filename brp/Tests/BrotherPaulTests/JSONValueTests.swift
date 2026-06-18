import XCTest
@testable import BrotherPaul

final class JSONValueTests: XCTestCase {

    func testDecodeMixedObject() throws {
        let json = #"{ "app": "Slack", "count": 3, "flag": true, "tags": ["a","b"] }"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        let obj = try XCTUnwrap(value.objectValue)
        XCTAssertEqual(obj["app"]?.stringValue, "Slack")
        XCTAssertEqual(obj["count"]?.intValue, 3)
        XCTAssertEqual(obj["flag"], .bool(true))
        XCTAssertEqual(obj["tags"]?.arrayValue?.count, 2)
    }

    func testEncodeRoundTrips() throws {
        let value: JSONValue = .object(["k": .string("v"), "n": .double(2)])
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(back, value)
    }

    func testIntValueFromWholeDouble() {
        XCTAssertEqual(JSONValue.double(8).intValue, 8)
        XCTAssertNil(JSONValue.string("x").intValue)
    }
}

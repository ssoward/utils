// brp/Tests/BrotherPaulTests/AgentToolsTests.swift
import XCTest
@testable import BrotherPaul

final class AgentToolsTests: XCTestCase {

    func testAllFourToolsAreDefined() {
        let names = Set(AgentTools.definitions().map(\.name))
        XCTAssertEqual(names, ["control_apps", "control_windows", "query_schedule", "run_system_action"])
    }

    func testEveryToolHasObjectSchema() {
        for tool in AgentTools.definitions() {
            XCTAssertFalse(tool.description.isEmpty, "\(tool.name) needs a description")
            guard case .object(let schema) = tool.input_schema else {
                return XCTFail("\(tool.name) input_schema must be an object")
            }
            XCTAssertEqual(schema["type"]?.stringValue, "object")
        }
    }

    @MainActor
    func testDispatchUnknownToolIsError() async {
        let registry = AgentToolRegistry(allowSystemControl: true)
        let outcome = await registry.dispatch(ToolCall(id: "1", name: "nope", input: [:]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testDispatchRoutesControlWindows() async {
        let registry = AgentToolRegistry(allowSystemControl: true)
        // Unknown zone → WindowControlExecutor returns an error; proves routing reached it.
        let outcome = await registry.dispatch(
            ToolCall(id: "1", name: "control_windows", input: ["zone": .string("nope")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.contains("zone"))
    }
}

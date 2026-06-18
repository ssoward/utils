// brp/Tests/BrotherPaulTests/MessagesAPITests.swift
import XCTest
@testable import BrotherPaul

final class MessagesAPITests: XCTestCase {

    func testDecodesToolUseResponse() throws {
        let json = """
        { "content": [
            { "type": "text", "text": "Opening Slack." },
            { "type": "tool_use", "id": "toolu_1", "name": "control_apps",
              "input": { "action": "open_app", "app": "Slack" } }
          ],
          "stop_reason": "tool_use" }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(resp.stop_reason, "tool_use")
        guard case .text(let t) = resp.content[0] else { return XCTFail("expected text") }
        XCTAssertEqual(t, "Opening Slack.")
        guard case .toolUse(let id, let name, let input) = resp.content[1] else { return XCTFail("expected tool_use") }
        XCTAssertEqual(id, "toolu_1")
        XCTAssertEqual(name, "control_apps")
        XCTAssertEqual(input["app"]?.stringValue, "Slack")
    }

    func testEncodesToolResultBlock() throws {
        let msg = APIMessage(role: "user", content: [
            .toolResult(toolUseId: "toolu_1", content: "Done.", isError: false)
        ])
        let data = try JSONEncoder().encode(msg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let block = (obj["content"] as! [[String: Any]])[0]
        XCTAssertEqual(block["type"] as? String, "tool_result")
        XCTAssertEqual(block["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(block["content"] as? String, "Done.")
    }

    func testRequestEncodesSystemCacheControlAndTools() throws {
        let req = MessagesRequest(
            model: "claude-opus-4-8",
            max_tokens: 1024,
            system: "You are Brother Paul.",
            tools: [APIToolDefinition(name: "control_apps", description: "d", input_schema: .object([:]))],
            messages: [APIMessage(role: "user", content: [.text("hi")])],
            effort: "medium"
        )
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let sys = obj["system"] as! [[String: Any]]
        XCTAssertEqual((sys[0]["cache_control"] as! [String: Any])["type"] as? String, "ephemeral")
        XCTAssertEqual((obj["thinking"] as! [String: Any])["type"] as? String, "adaptive")
        XCTAssertEqual((obj["output_config"] as! [String: Any])["effort"] as? String, "medium")
    }
}

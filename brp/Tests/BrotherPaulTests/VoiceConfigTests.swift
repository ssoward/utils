// brp/Tests/BrotherPaulTests/VoiceConfigTests.swift
import XCTest
@testable import BrotherPaul

final class VoiceConfigTests: XCTestCase {

    func testDefaultsAreSafe() {
        let v = VoiceConfig.default
        XCTAssertFalse(v.enabled)                 // master switch OFF by default
        XCTAssertEqual(v.model, "claude-opus-4-8")
        XCTAssertEqual(v.effort, "medium")
        XCTAssertEqual(v.maxTokens, 1024)
        XCTAssertTrue(v.speakReplies)
        XCTAssertTrue(v.allowSystemControl)
        XCTAssertEqual(v.confirmTier, "tiered")
        XCTAssertTrue(v.wakeWord.enabled)
        XCTAssertTrue(v.pushToTalkFallback)
    }

    func testOlderConfigWithoutVoiceBlockDecodesToDefault() throws {
        // A config.json from before this feature existed.
        let json = """
        { "hideOthersAfterLaunch": true, "defaultMode": "Full", "modes": [] }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.voice, VoiceConfig.default)
    }

    func testVoiceBlockRoundTrips() throws {
        var v = VoiceConfig.default
        v.enabled = true
        v.model = "claude-haiku-4-5"
        let config = AppConfig(hideOthersAfterLaunch: true, defaultMode: "Full", modes: [], voice: v)
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(back.voice, v)
    }
}

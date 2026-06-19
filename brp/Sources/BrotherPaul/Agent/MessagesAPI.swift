// brp/Sources/BrotherPaul/Agent/MessagesAPI.swift
import Foundation

enum APIContentBlock: Codable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, tool_use_id, content, is_error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                input: try c.decode([String: JSONValue].self, forKey: .input))
        case "tool_result":
            self = .toolResult(
                toolUseId: try c.decode(String.self, forKey: .tool_use_id),
                content: try c.decode(String.self, forKey: .content),
                isError: try c.decodeIfPresent(Bool.self, forKey: .is_error) ?? false)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown content block type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .tool_use_id)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .is_error)
        }
    }
}

struct APIMessage: Codable, Equatable {
    let role: String
    let content: [APIContentBlock]
}

struct APIToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: JSONValue
}

struct MessagesResponse: Decodable {
    let content: [APIContentBlock]
    let stop_reason: String?
}

struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: [SystemBlock]
    let tools: [APIToolDefinition]
    let messages: [APIMessage]
    let thinking: Thinking
    let output_config: OutputConfig

    init(model: String, max_tokens: Int, system: String,
         tools: [APIToolDefinition], messages: [APIMessage], effort: String) {
        self.model = model
        self.max_tokens = max_tokens
        self.system = [SystemBlock(text: system)]
        self.tools = tools
        self.messages = messages
        self.thinking = Thinking()
        self.output_config = OutputConfig(effort: effort)
    }

    struct SystemBlock: Encodable {
        let type = "text"
        let text: String
        let cache_control = CacheControl()
        struct CacheControl: Encodable { let type = "ephemeral" }
    }
    struct Thinking: Encodable {
        let type = "adaptive"
        let display = "omitted"
    }
    struct OutputConfig: Encodable {
        let effort: String
    }
}

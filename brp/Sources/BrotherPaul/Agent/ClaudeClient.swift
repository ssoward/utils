// brp/Sources/BrotherPaul/Agent/ClaudeClient.swift
import Foundation

protocol MessagesTransport {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
}

enum ClaudeClientError: Error, Equatable {
    case missingAPIKey
    case refused(String)
    case httpError(Int)
}

final class ClaudeClient {
    private let config: VoiceConfig
    private let tools: [APIToolDefinition]
    private let systemPrompt: String
    private let secrets: SecretStore
    private let transport: MessagesTransport

    /// Conversation history, preserved across calls within one ClaudeClient instance.
    private var history: [APIMessage] = []

    /// Safety valve against runaway tool loops.
    private let maxIterations = 8

    init(config: VoiceConfig, tools: [APIToolDefinition], systemPrompt: String,
         secrets: SecretStore, transport: MessagesTransport) {
        self.config = config
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.secrets = secrets
        self.transport = transport
    }

    /// Send a user transcript, run the tool-use loop, return the final spoken text.
    func send(_ transcript: String,
              confirm: @escaping (ToolCall) async -> Bool,
              execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String {
        guard secrets.get(SecretKey.anthropicAPIKey) != nil else { throw ClaudeClientError.missingAPIKey }

        history.append(APIMessage(role: "user", content: [.text(transcript)]))

        for _ in 0..<maxIterations {
            let request = MessagesRequest(
                model: config.model, max_tokens: config.maxTokens, system: systemPrompt,
                tools: tools, messages: history, effort: config.effort)
            let response = try await transport.send(request)

            if response.stop_reason == "refusal" {
                throw ClaudeClientError.refused(firstText(response.content) ?? "Request was refused.")
            }

            history.append(APIMessage(role: "assistant", content: response.content))

            let toolCalls = response.content.compactMap { block -> ToolCall? in
                if case .toolUse(let id, let name, let input) = block {
                    return ToolCall(id: id, name: name, input: input)
                }
                return nil
            }

            if toolCalls.isEmpty || response.stop_reason == "end_turn" {
                return firstText(response.content) ?? ""
            }

            var results: [APIContentBlock] = []
            for call in toolCalls {
                let outcome: ExecutionOutcome
                if ToolRiskClassifier.risk(for: call) == .confirm {
                    let approved = await confirm(call)
                    outcome = approved ? await execute(call) : .ok("User declined this action.")
                } else {
                    outcome = await execute(call)
                }
                results.append(.toolResult(toolUseId: call.id, content: outcome.content, isError: outcome.isError))
            }
            history.append(APIMessage(role: "user", content: results))
        }

        return "I wasn't able to finish that — it took too many steps."
    }

    private func firstText(_ blocks: [APIContentBlock]) -> String? {
        for block in blocks { if case .text(let t) = block { return t } }
        return nil
    }
}

/// Real HTTP transport against the Anthropic Messages API.
final class URLSessionTransport: MessagesTransport {
    private let secrets: SecretStore
    private let session: URLSession
    private let url = URL(string: "https://api.anthropic.com/v1/messages")!

    init(secrets: SecretStore, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard let key = secrets.get(SecretKey.anthropicAPIKey) else { throw ClaudeClientError.missingAPIKey }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            NSLog("BrotherPaul: Anthropic API error %d — %@", http.statusCode,
                  String(data: data, encoding: .utf8) ?? "")
            throw ClaudeClientError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }
}

//
//  OpenAICompatibleChatProvider.swift
//  leanring-buddy
//
//  Chat/vision provider for any OpenAI-compatible endpoint. This covers
//  tokenharbor (https://tokenharbor.ai/v1), LM Studio (http://localhost:1234/v1),
//  and other local servers such as Ollama or vLLM.
//
//  Wire-format differences from Anthropic that this provider handles:
//   - Endpoint:  POST {baseURL}/chat/completions
//   - Images:    {"type":"image_url","image_url":{"url":"data:<mime>;base64,..."}}
//   - Streaming: SSE where each chunk is choices[].delta.content
//

import Foundation

final class OpenAICompatibleChatProvider: ChatProvider {
    var model: String
    let providerDisplayName: String

    private let chatCompletionsURL: URL
    private let apiKey: String?
    private let session: URLSession

    private static let tlsWarmupLock = NSLock()
    private static var hasStartedTLSWarmup = false

    /// - Parameters:
    ///   - baseURL: OpenAI-style API root, e.g. "https://tokenharbor.ai/v1"
    ///     or "http://localhost:1234/v1". "/chat/completions" is appended.
    ///   - model: Model identifier for the backend.
    ///   - apiKey: Bearer token, or nil/empty for local servers that need none.
    ///   - providerDisplayName: Shown in the Settings panel and logs.
    init(baseURL: String, model: String, apiKey: String?, providerDisplayName: String) {
        self.model = model
        self.providerDisplayName = providerDisplayName

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.chatCompletionsURL = URL(string: "\(trimmedBaseURL)/chat/completions")!

        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmedAPIKey?.isEmpty ?? true) ? nil : trimmedAPIKey

        // Use .default instead of .ephemeral so TLS session tickets are cached.
        // Local (http) servers ignore this; it only matters for cloud HTTPS.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)

        warmUpTLSConnectionIfNeeded()
    }

    /// Sends a no-op HEAD request to warm the TLS session ticket so the first
    /// real call (which carries large base64 images) avoids a cold handshake.
    /// Skipped for plain-http local endpoints, where it has no benefit.
    private func warmUpTLSConnectionIfNeeded() {
        guard chatCompletionsURL.scheme?.lowercased() == "https" else { return }

        Self.tlsWarmupLock.lock()
        let shouldStartTLSWarmup = !Self.hasStartedTLSWarmup
        if shouldStartTLSWarmup { Self.hasStartedTLSWarmup = true }
        Self.tlsWarmupLock.unlock()

        guard shouldStartTLSWarmup else { return }
        guard var warmupURLComponents = URLComponents(url: chatCompletionsURL, resolvingAgainstBaseURL: false) else {
            return
        }

        // The TLS session ticket is host-scoped, so warming the root host is enough.
        warmupURLComponents.path = "/"
        warmupURLComponents.query = nil
        warmupURLComponents.fragment = nil
        guard let warmupURL = warmupURLComponents.url else { return }

        var warmupRequest = URLRequest(url: warmupURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in
            // Response doesn't matter — the TLS handshake is the goal.
        }.resume()
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // OpenAI-style messages: a leading system message, then the history,
        // then the current user turn carrying labeled images + the prompt.
        var messages: [[String: Any]] = []
        messages.append(["role": "system", "content": systemPrompt])

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
            let mediaType = ChatProviderImageSupport.detectMediaType(for: image.data)
            contentBlocks.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(mediaType);base64,\(image.data.base64EncodedString())"
                ]
            ])
        }
        contentBlocks.append(["type": "text", "text": userPrompt])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 \(providerDisplayName) streaming request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s), model=\(model)")

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleChatProviderError(
                message: "Invalid HTTP response from \(providerDisplayName)"
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyLines: [String] = []
            for try await line in byteStream.lines {
                errorBodyLines.append(line)
            }
            let errorBody = errorBodyLines.joined(separator: "\n")
            throw OpenAICompatibleChatProviderError(
                message: "\(providerDisplayName) API error (\(httpResponse.statusCode)): \(errorBody)"
            )
        }

        // Parse SSE — each event is "data: {json}" and the stream ends with
        // "data: [DONE]". Content chunks live at choices[0].delta.content.
        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = eventPayload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let textChunk = delta["content"] as? String,
                  !textChunk.isEmpty else {
                continue
            }

            accumulatedResponseText += textChunk
            let currentAccumulatedText = accumulatedResponseText
            await onTextChunk(currentAccumulatedText)
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }
}

struct OpenAICompatibleChatProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

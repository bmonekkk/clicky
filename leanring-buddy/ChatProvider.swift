//
//  ChatProvider.swift
//  leanring-buddy
//
//  Shared protocol surface for AI chat/vision backends. Every provider
//  (Anthropic, tokenharbor, LM Studio, ...) conforms to this so the
//  CompanionManager response pipeline stays backend-agnostic.
//
//  The method contract deliberately mirrors the original
//  `ClaudeAPI.analyzeImageStreaming` signature so existing call sites do not
//  need to know which backend is in use.
//

import Foundation

/// Any chat/vision backend the companion can talk to.
protocol ChatProvider: AnyObject {
    /// The model identifier sent to the backend (e.g. "claude-sonnet-4-6",
    /// "deepseek-v4.1-flash:free"). Settable so the Settings UI can change it
    /// at runtime without rebuilding the provider object.
    var model: String { get set }

    /// Human-readable backend name, used in logs and the Settings panel.
    var providerDisplayName: String { get }

    /// Sends labeled screenshots plus the user's prompt and streams the reply.
    ///
    /// - Parameters:
    ///   - images: One entry per captured screen. Each carries raw image bytes
    ///     (JPEG or PNG) and a text label describing that screen.
    ///   - systemPrompt: The companion's persona/instructions.
    ///   - conversationHistory: Prior exchanges, replayed as context.
    ///   - userPrompt: What the user just said.
    ///   - onTextChunk: Called on the main actor with the accumulated text each
    ///     time new content arrives, for progressive UI updates.
    /// - Returns: The full accumulated response text and how long it took.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval)
}

/// Shared image-format detection so every provider declares the correct MIME
/// type. The API rejects requests when the declared type doesn't match the
/// actual bytes (screen captures are JPEG, pasted clipboard images are PNG).
enum ChatProviderImageSupport {
    /// Inspects the first bytes of `imageData` and returns the matching MIME type.
    static func detectMediaType(for imageData: Data) -> String {
        // PNG files start with the 8-byte signature: 89 50 4E 47 0D 0A 1A 0A
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            if [UInt8](imageData.prefix(4)) == pngSignature {
                return "image/png"
            }
        }
        // Default to JPEG — screen captures use JPEG compression.
        return "image/jpeg"
    }
}

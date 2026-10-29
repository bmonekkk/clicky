//
//  ChatProviderConfiguration.swift
//  leanring-buddy
//
//  User-configurable chat/vision backend settings, persisted to UserDefaults.
//  The Settings panel edits these values and CompanionManager rebuilds its
//  ChatProvider from them whenever they change.
//

import Foundation

/// Which wire protocol/backend the app talks to.
enum ChatProviderKind: String, Codable {
    /// Anthropic Messages API, normally reached through the Cloudflare Worker.
    case anthropic
    /// Any OpenAI-compatible endpoint (tokenharbor cloud, LM Studio local, ...).
    case openAICompatible
}

/// One-click presets shown in the Settings panel. Everything they set is then
/// editable, so a preset is just a convenient starting point.
enum ChatProviderPreset: String, CaseIterable {
    case anthropic
    case tokenHarbor
    case lmStudio

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .tokenHarbor: return "tokenharbor"
        case .lmStudio: return "LM Studio"
        }
    }

    /// The starting configuration for this preset.
    func configuration(defaultAnthropicBaseURL: String) -> ChatProviderConfiguration {
        switch self {
        case .anthropic:
            return ChatProviderConfiguration(
                providerDisplayName: "Anthropic Claude",
                kind: .anthropic,
                baseURL: defaultAnthropicBaseURL,
                model: "claude-sonnet-4-6",
                apiKey: ""
            )
        case .tokenHarbor:
            return ChatProviderConfiguration(
                providerDisplayName: "tokenharbor",
                kind: .openAICompatible,
                baseURL: "https://tokenharbor.ai/v1",
                model: "deepseek-v4.1-flash:free",
                apiKey: ""
            )
        case .lmStudio:
            return ChatProviderConfiguration(
                providerDisplayName: "LM Studio",
                kind: .openAICompatible,
                baseURL: "http://localhost:1234/v1",
                model: "qwen3.8-27b",
                apiKey: ""
            )
        }
    }
}

/// The active chat/vision backend settings.
struct ChatProviderConfiguration: Codable, Equatable {
    /// Friendly name shown in the panel, e.g. "tokenharbor" or "LM Studio".
    var providerDisplayName: String
    /// Which wire protocol to speak.
    var kind: ChatProviderKind
    /// API root. For Anthropic this is the Worker base URL; for
    /// OpenAI-compatible it's the provider root (tokenharbor/LM Studio).
    var baseURL: String
    /// Model identifier sent to the backend.
    var model: String
    /// Bearer token for OpenAI-compatible cloud backends. Empty for local.
    var apiKey: String

    private static let userDefaultsKey = "chatProviderConfiguration"

    /// Reads the saved configuration, falling back to the Anthropic default.
    static func load(defaultAnthropicBaseURL: String) -> ChatProviderConfiguration {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(ChatProviderConfiguration.self, from: data) {
            return saved
        }
        return ChatProviderPreset.anthropic.configuration(defaultAnthropicBaseURL: defaultAnthropicBaseURL)
    }

    /// Persists this configuration so it survives app restarts.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Short one-line summary for the panel, e.g. "tokenharbor · deepseek-v4.1-flash:free".
    var summary: String {
        "\(providerDisplayName) · \(model)"
    }
}

/// Remembers API keys per provider so switching presets in the panel doesn't
/// wipe a key the user already typed. Keys are stored in UserDefaults keyed by
/// the provider's display name (e.g. "tokenharbor"), which is why the active
/// `ChatProviderConfiguration.apiKey` can be blank for one provider without
/// losing the key for another.
enum ChatProviderAPIKeyStore {
    private static let userDefaultsKey = "chatProviderAPIKeysByProviderName"

    /// The saved key for a provider, or an empty string if none was saved.
    static func apiKey(forProviderNamed providerDisplayName: String) -> String {
        allStoredKeys()[providerDisplayName] ?? ""
    }

    /// Saves (or clears, when empty) the key for a provider.
    static func setAPIKey(_ apiKey: String, forProviderNamed providerDisplayName: String) {
        var updatedKeys = allStoredKeys()
        if apiKey.isEmpty {
            updatedKeys.removeValue(forKey: providerDisplayName)
        } else {
            updatedKeys[providerDisplayName] = apiKey
        }
        UserDefaults.standard.set(updatedKeys, forKey: userDefaultsKey)
    }

    private static func allStoredKeys() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
    }
}

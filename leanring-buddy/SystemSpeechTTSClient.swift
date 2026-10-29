//
//  SystemSpeechTTSClient.swift
//  leanring-buddy
//
//  Free, offline text-to-speech using the macOS system voice
//  (AVSpeechSynthesizer). This is a drop-in replacement for
//  ElevenLabsTTSClient so the companion can speak responses without any
//  paid API, network access, or API key.
//

import AVFoundation
import Foundation

@MainActor
final class SystemSpeechTTSClient: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    /// Resumed when the current utterance finishes or is cancelled, so
    /// `speakText` can be awaited until playback completes.
    private var currentUtteranceContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` and returns once playback finishes (or is stopped).
    /// Matches `ElevenLabsTTSClient.speakText` so call sites stay unchanged.
    func speakText(_ text: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Cancel anything already speaking so responses don't overlap.
        stopPlayback()

        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = Self.englishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            currentUtteranceContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    /// Whether speech is currently playing back.
    var isPlaying: Bool {
        synthesizer.isSpeaking
    }

    /// The voice used for playback. This fork always speaks English, even when
    /// the Mac's system language is set to something else (e.g. Polish). Picks
    /// a US English voice by identifier, falling back to any installed English
    /// voice, then to the system default if none is installed.
    private static func englishVoice() -> AVSpeechSynthesisVoice? {
        if let usEnglishVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha") {
            return usEnglishVoice
        }
        if let anyEnglishVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") }) {
            return anyEnglishVoice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resumeContinuationIfNeeded()
    }

    private func resumeContinuationIfNeeded() {
        if let continuation = currentUtteranceContinuation {
            currentUtteranceContinuation = nil
            continuation.resume()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeContinuationIfNeeded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeContinuationIfNeeded() }
    }
}

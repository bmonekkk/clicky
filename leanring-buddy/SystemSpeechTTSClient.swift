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
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
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

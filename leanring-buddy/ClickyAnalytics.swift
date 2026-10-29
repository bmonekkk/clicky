//
//  ClickyAnalytics.swift
//  leanring-buddy
//
//  Analytics facade. Upstream Clicky sent usage events, including the user's
//  voice transcripts and the AI's responses, to the author's PostHog project.
//  This fork disables that entirely: every method below is a no-op, so no
//  telemetry leaves the machine.
//
//  The method names are kept so existing call sites don't need to change. If
//  you ever want analytics back, point them at your own project and make sure
//  you never send transcript or response content.
//

import Foundation

enum ClickyAnalytics {

    // MARK: - Setup

    static func configure() {
        // Intentionally does nothing. No analytics SDK is started.
    }

    // MARK: - App Lifecycle

    static func trackAppOpened() {}

    // MARK: - Onboarding

    static func trackOnboardingStarted() {}

    static func trackOnboardingReplayed() {}

    static func trackOnboardingVideoCompleted() {}

    static func trackOnboardingDemoTriggered() {}

    // MARK: - Permissions

    static func trackAllPermissionsGranted() {}

    static func trackPermissionGranted(permission: String) {}

    // MARK: - Voice Interaction

    static func trackPushToTalkStarted() {}

    static func trackPushToTalkReleased() {}

    static func trackUserMessageSent(transcript: String) {}

    static func trackAIResponseReceived(response: String) {}

    static func trackElementPointed(elementLabel: String?) {}

    // MARK: - Errors

    static func trackResponseError(error: String) {}

    static func trackTTSError(error: String) {}
}
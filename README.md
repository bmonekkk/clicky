# Clicky — multi-provider fork

A fork of [farzaa/clicky](https://github.com/farzaa/clicky) (MIT) that runs on
**tokenharbor cloud models** and **LM Studio local models**, with **free,
offline voice** and no first-run onboarding or email gate.

macOS menu-bar app (no dock icon, no main window). Press **Control + Option**,
speak, release: Clicky transcribes you, sends the transcript plus a screenshot
to the configured model, speaks the answer, and can fly a blue cursor to point
at things on screen.

## What's different in this fork

- **Pluggable chat/vision backend** behind a `ChatProvider` protocol
  (`Anthropic`, `tokenharbor`, `LM Studio`, or any OpenAI-compatible endpoint).
- **Model settings are editable in the panel** — provider preset, base URL,
  model, and API key. No recompiling to switch models.
- **Free voice** — Apple on-device Speech for STT and macOS system TTS
  (`AVSpeechSynthesizer`) for playback. No AssemblyAI or ElevenLabs
  subscription required. Both are forced to **English**.
- **No onboarding** — the intro video, welcome animation, "Start" button, and
  email gate are removed. Grant permissions and go.
- **Telemetry removed** — this fork does not start PostHog (upstream sent
  transcripts and responses to the author's analytics project).
- **No auto-updater** — the upstream Sparkle appcast is removed, so the fork
  never replaces itself with an unrelated release.
- **Terminal build scripts** — `scripts/build-local.sh` + `scripts/run-local.sh`
  build and run with ad-hoc signing, no Apple Developer account or Xcode GUI.

## Requirements

- macOS 14.2 or later (ScreenCaptureKit)
- Xcode (for the build toolchain)
- Node.js 18+ (only if you deploy the optional Cloudflare Worker)

## Build and run

```bash
scripts/build-local.sh     # builds build/Build/Products/Debug/Clicky.app
scripts/run-local.sh       # launches it
```

The app appears in the **menu bar**, not the dock. Click the icon and grant the
four permissions it lists: **Microphone**, **Accessibility**, **Screen
Recording**, and **Screen Content**.

> Ad-hoc signing means the app's signature changes on every rebuild, so macOS
> may ask you to re-grant Screen Recording / Accessibility after a rebuild.
> After granting Screen Recording, quit and reopen the app.

## Configure a model

Open the menu-bar panel → **AI MODEL**. Pick a preset, adjust the fields, and
click **Save Model Settings**:

| Preset | Base URL | Notes |
|---|---|---|
| **tokenharbor** | `https://tokenharbor.ai/v1` | Paste your tokenharbor API key. Default model: `deepseek-v4.1-flash:free`. |
| **LM Studio** | `http://localhost:1234/v1` | Point at `http://<LAN-IP>:1234/v1` for a model on another machine. No API key. |
| **Anthropic** | your Worker URL | Requires the optional Worker below. The key stays on the Worker. |

The local model **must be vision-capable** to see screenshots. The fork was
tested with `deepseek-v4.1-flash:free`; LM Studio trials were set up for
`qwen3.8-27b`, `gemma4-26b`, and `gemma4-12b`.

API keys typed into the panel are stored per provider in the app's
`UserDefaults` (plaintext, under `~/Library/Preferences/`). See
[Security & privacy](#security--privacy).

## Optional: Cloudflare Worker gateway

The Worker lets the app use cloud models without shipping the provider key in
the app binary. It is only needed for cloud providers; LM Studio is called
directly over the network and never touches the Worker.

```bash
cd worker
npm install
npx wrangler secret put TOKENHARBOR_API_KEY
# Optional, only if you still use these upstream routes:
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler deploy
```

Then set the app's **Base URL** to `<your-worker-url>/v1`, choose the
tokenharbor preset's model name, and leave the API key blank — the Worker
injects the real key.

Routes: `POST /v1/chat/completions`, `GET /v1/models`, `POST /chat`
(Anthropic), `POST /tts`, `POST /transcribe-token`.

For local Worker development, create `worker/.dev.vars` (gitignored) with the
secrets and run `npx wrangler dev`.

## Security & privacy

- **No telemetry.** `ClickyAnalytics` is a no-op facade; no analytics SDK is
  started and no transcript/response content leaves the machine.
- **No silent auto-update.** Sparkle is not started and the upstream appcast
  URL/key were removed.
- **Screenshots** are captured only while the push-to-talk interaction runs
  and are sent to the model you configured.
- **API keys** are stored locally in `UserDefaults`, not in the repo. They are
  not encrypted at rest; this is a deliberate trade-off for ad-hoc-signed
  builds. Use a scoped/limited key.
- **Worker trust model.** Anyone who knows your deployed Worker URL can send
  requests through it and spend your credits. Keep the URL private or use a
  scoped key. For local LM Studio, nothing leaves your network.
- **Sandbox is disabled** (`com.apple.security.app-sandbox = false`) because
  the app needs ScreenCaptureKit and LAN access. Review entitlements in
  `leanring-buddy/leanring-buddy.entitlements` before distributing.

## Project structure

```
leanring-buddy/                 # Swift source (the "leanring" typo is upstream)
  CompanionManager.swift          # Central state machine
  CompanionPanelView.swift        # Menu-bar panel UI
  ChatProvider.swift              # Backend protocol
  OpenAICompatibleChatProvider.swift
  ChatProviderConfiguration.swift # Presets + per-provider key store
  ClaudeAPI.swift                 # Anthropic client
  AppleSpeechTranscriptionProvider.swift
  SystemSpeechTTSClient.swift     # Free system TTS
  OverlayWindow.swift             # Blue cursor overlay
  ClickyAnalytics.swift           # No-op analytics facade
worker/                         # Optional Cloudflare Worker proxy
scripts/build-local.sh          # Ad-hoc local build
scripts/run-local.sh            # Launch the built app
AGENTS.md                       # Architecture + agent instructions
```

## Upstream

This is a personal fork. The original project and official downloads are at
[heyclicky.com](https://www.heyclicky.com/); the upstream source is
[farzaa/clicky](https://github.com/farzaa/clicky). Licensed under MIT — see
[LICENSE](LICENSE).
# HeyClicky Fork — Plan: Multi-Provider Models + Free Voice

Status: **IMPLEMENTED** (see §10 Outcome)
Author: OpenCode agent
Date: 2026-10-29
Repo: forked from `https://github.com/farzaa/clicky` (MIT)
Local path: `~/projects/HeyClicky`

---

## 1. Goal

Turn Clicky into a model-agnostic, mostly-free desktop buddy:

1. **Cloud models** via tokenharbor (OpenAI-compatible) — starting with `deepseek-v4.1-flash:free`.
2. **Local models** via LM Studio on this Mac *or* a LAN PC — base URL fully configurable.
3. **Free voice** — no AssemblyAI / ElevenLabs subscriptions. Use Apple's on-device
   Speech framework for STT and system TTS for playback.
4. Everything **configurable from the app's menu-bar panel**, not hardcoded.

Non-goals: no UI redesign, no Windows port, no removal of the Anthropic path
(it stays as an optional provider).

---

## 2. What exists today

macOS menu-bar app (`LSUIElement=true`) + a 141-line Cloudflare Worker proxy.

**Data flow (current):**

```
ctrl+option  →  AVAudioEngine mic
             →  AssemblyAI websocket (u3-rt-pro)        [STT]
             →  ScreenCaptureKit screenshot(s)
             →  POST /chat  → Worker → api.anthropic.com  [chat + vision, SSE]
             →  POST /tts   → Worker → ElevenLabs         [TTS]
             →  [POINT:x,y:label:screenN] tag → cursor overlay animation
```

**Key integration points (file:line) that the fork touches:**

| What | Where |
|---|---|
| Hardcoded Worker base URL | `leanring-buddy/CompanionManager.swift:73` |
| `claudeAPI` singleton | `leanring-buddy/CompanionManager.swift:75-77` |
| `elevenLabsTTSClient` singleton | `leanring-buddy/CompanionManager.swift:79-81` |
| Model selection + persistence | `leanring-buddy/CompanionManager.swift:111-117` |
| Main response pipeline | `leanring-buddy/CompanionManager.swift:586-726` |
| TTS call in pipeline | `leanring-buddy/CompanionManager.swift:704` |
| TTS `isPlaying` wait | `leanring-buddy/CompanionManager.swift:738` |
| Existing system-TTS fallback (precedent!) | `leanring-buddy/CompanionManager.swift:761-766` |
| `[POINT:...]` parser (provider-agnostic, no change) | `leanring-buddy/CompanionManager.swift:784-823` |
| Hardcoded model picker | `leanring-buddy/CompanionPanelView.swift:601-642` |
| Anthropic client (SSE) | `leanring-buddy/ClaudeAPI.swift` |
| OpenAI-shaped client (dead code, head start) | `leanring-buddy/OpenAIAPI.swift` |
| STT provider factory | `leanring-buddy/BuddyTranscriptionProvider.swift:32-99` |
| Apple Speech STT (already built, unused) | `leanring-buddy/AppleSpeechTranscriptionProvider.swift` |
| STT selection (Info.plist key) | `leanring-buddy/Info.plist:11-12` (`VoiceTranscriptionProvider = assemblyai`) |
| Worker proxy | `worker/src/index.ts` |

**What Clicky runs on today:** chat/vision = `claude-sonnet-4-6` (default) or
`claude-opus-4-6`; STT = AssemblyAI `u3-rt-pro`; TTS = ElevenLabs `eleven_flash_v2_5`.

---

## 3. Verified facts (measured, not assumed)

### 3.1 tokenharbor is OpenAI-compatible
From `~/.config/opencode/opencode.json`:
```
provider.tokenharbor = { npm: "@ai-sdk/openai-compatible",
                         baseURL: "https://tokenharbor.ai/v1",
                         apiKey: "{env:TOKENHARBOR_API_KEY}" }
```
`TOKENHARBOR_API_KEY` is present in the environment (73 chars).

### 3.2 Vision probe results (real requests sent during planning)

Test = generated PNG (solid blue; and red-left/blue-right split), asked to identify.

| Model | Vision? | Notes |
|---|---|---|
| `deepseek-v4.1-flash:free` | ✅ yes | correctly read colors + left/right |
| `mimo-v2.6-flash:free` | ✅ yes | correctly read colors + left/right |
| `qwen3.8-27b` | ⛔ HTTP 402 | balance $0 |
| `gemini-3.8-flash` | ⛔ HTTP 402 | balance $0 |
| `glm-5.3` | ⛔ HTTP 402 | balance $0 |
| `gpt-6-astra` | ⛔ HTTP 402 | balance $0 |
| `claude-sonnet-5.5` | ⛔ HTTP 402 | balance $0 |
| `kimi-k3` | ⛔ HTTP 402 | balance $0 |

**Conclusion:** only `:free` models are usable until the tokenharbor balance is
topped up. Both free models have working vision. Default = `deepseek-v4.1-flash:free`.

### 3.3 Build environment
- Xcode **27.1** (`/Applications/Xcode.app`), macOS 27.0 SDK, macOS 27.2, Swift 6.4.
- `xcode-select` → CommandLineTools, so bare `xcodebuild` fails, **but**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …` works.
- Xcode license already accepted (verified by `xcodebuild -version` succeeding).
- Project hardcodes `DEVELOPMENT_TEAM` + `CODE_SIGN_STYLE = Automatic` → must be
  overridden on the CLI for ad-hoc signing.
- Entitlements: **app-sandbox = false**, network client = true → screen capture
  and arbitrary HTTP (LAN LM Studio) are allowed.

---

## 4. Target architecture

```
                          ┌─────────────────────────────┐
  CompanionManager ──────▶│  ChatProvider (protocol)     │
  (state machine)         │   analyzeImageStreaming(...)  │
                          └──────────┬──────────────────┘
                                     │
             ┌───────────────────────┼────────────────────────┐
             ▼                       ▼                        ▼
   AnthropicChatProvider   OpenAICompatibleChatProvider   (future: others)
   (= refactored ClaudeAPI)         │
             │               baseURL chosen at runtime:
             │               • https://tokenharbor.ai/v1   (cloud, key via Worker)
             │               • http://localhost:1234/v1    (LM Studio, this Mac)
   Worker /chat ─────────────┘• http://192.168.x.x:1234/v1 (LM Studio, LAN PC)
```

- The app speaks **one** interface; each provider adapts to its wire format.
- The `[POINT:...]` parser, overlay, screen capture, and conversation history are
  **provider-agnostic and unchanged**.
- LM Studio is called **directly over the LAN** (never through Cloudflare).
- tokenharbor/Anthropic go through the Worker so keys don't ship in the binary.

**Streaming format difference (the crux):**
- Anthropic SSE: `content_block_delta` → `delta.text_delta.text`
- OpenAI SSE: `choices[].delta.content`

**Vision payload difference:**
- Anthropic: `{"type":"image","source":{"type":"base64","media_type":…,"data":…}}`
- OpenAI: `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}`

---

## 5. Phases

Each phase ends with a checkpoint. I will not proceed past a phase without your OK.

### Phase 0 — Fork hygiene
- Create branch `feature/multi-provider-free-voice` off `main`.
- Add `PLAN.md` (this file).
- Leave `origin` pointing at upstream; you can later add your own fork remote.

### Phase 1 — Provider abstraction (Swift)
**New files**
- `leanring-buddy/ChatProvider.swift` — protocol matching the existing
  `ClaudeAPI.analyzeImageStreaming` signature, so call sites don't change.
- `leanring-buddy/OpenAICompatibleChatProvider.swift` — base URL + model + key;
  OpenAI `messages` schema, `image_url` data-URL images, SSE parsing of
  `choices[].delta.content`; configurable token-limit field
  (`max_tokens` for LM Studio/tokenharbor, `max_completion_tokens` optional).

**Changed files**
- `ClaudeAPI.swift` — conform to `ChatProvider` (no behavior change).
- `CompanionManager.swift` — replace `claudeAPI` with a `chatProvider` built from
  runtime config; rebuild when config changes. `setSelectedModel` → `updateChatConfiguration`.
- Register the two new files in `leanring-buddy.xcodeproj/project.pbxproj`.

**Risk:** hand-editing `.pbxproj`. Mitigation: add file references using the same
UUID style as existing entries, then verify the project still opens/parses
(`xcodebuild -list`).

### Phase 2 — Config model + Settings UI
**New file**
- `leanring-buddy/ChatProviderConfiguration.swift` — enum `ProviderKind`
  (`.anthropic`, `.openAICompatible`), `displayName`, `baseURL`, `model`, `apiKey`,
  `useWorker`; load/save via `UserDefaults`.

**Changed file**
- `CompanionPanelView.swift:601-642` — replace the 2-button Sonnet/Opus picker with:
  - Provider segmented control (Local / tokenharbor / Custom)
  - Base URL field (prefilled `http://localhost:1234/v1` or `https://tokenharbor.ai/v1`)
  - Model field (prefilled `deepseek-v4.1-flash:free`)
  - API key secure field (tokenharbor only; empty for LM Studio)
  - Uses existing `DS` design system + `.pointerCursor()` convention.

### Phase 3 — Worker gateway
**Changed file** `worker/src/index.ts`
- `/chat` routes by a `provider` field (or `X-Clicky-Provider` header):
  - `anthropic` → existing `api.anthropic.com/v1/messages`
  - `openai` → `https://tokenharbor.ai/v1/chat/completions` with
    `Authorization: Bearer ${env.TOKENHARBOR_API_KEY}`
- **New `GET /models`** route → proxies `https://tokenharbor.ai/v1/models` so the
  Settings panel can populate a model dropdown instead of a free-text field.
- Add secret `TOKENHARBOR_API_KEY`; keep Anthropic/TTS routes intact.
- Document `npx wrangler secret put TOKENHARBOR_API_KEY` in README.

**Confirmed:** yes to the `/models` proxy (panel gets a model dropdown).

**Note:** LM Studio never hits the Worker. This keeps local inference private.

### Phase 4 — Free voice
**STT (near-zero code):**
- Set `VoiceTranscriptionProvider = apple` in `Info.plist:12`.
- `AppleSpeechTranscriptionProvider` already exists, already on-device
  (`requiresOnDeviceRecognition = true`), already wires the permission flow.

**TTS (new file):**
- `leanring-buddy/SystemSpeechTTSClient.swift` — same public surface as
  `ElevenLabsTTSClient` (`speakText`, `isPlaying`, `stopPlayback`) backed by
  `AVSpeechSynthesizer` (async completion via delegate/continuation).
- Swap usages in `CompanionManager.swift` (lines 79-81, 496, 588, 704, 738).
- `speakCreditsErrorFallback()` (line 761) already proves system TTS works here.

**Result:** zero paid APIs. Only cost is the cloud model call (or nothing, if LM Studio).

### Phase 5 — Build, sign (ad-hoc), run
Build command (ad-hoc signing, overrides the hardcoded team):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project leanring-buddy.xcodeproj -scheme leanring-buddy \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Run:
```bash
open build/Build/Products/Debug/leanring-buddy.app
```
Then grant: Microphone, Accessibility, Screen Recording, Screen Content.
**Caveat (from repo AGENTS.md):** ad-hoc builds get a new cdhash each rebuild, so
macOS re-prompts for TCC permissions after every rebuild. Acceptable for dev.
(A self-signed stable identity is the later fix if it becomes annoying.)

**Deliverable:** a `scripts/build-local.sh` wrapper so you can rebuild in one command,
plus a short README section with the exact steps.

---

## 6. Risks & unknowns

| Risk | Impact | Mitigation |
|---|---|---|
| `.pbxproj` hand-edit breaks project | Won't build | Verify with `xcodebuild -list` after each edit |
| tokenharbor free tier rate limits | Slow/blocked responses | Configurable model; switch to LM Studio |
| 27B local model latency (first token) | Sluggish UX | Keep model + base URL configurable; document expectations |
| Local model ignores `[POINT:...]` tags | No pointing | Prompt tuning; pointing is optional/degradable |
| Ad-hoc TCC re-prompts | Repeated permission grants | Documented; optional self-signed cert later |
| LM Studio model must be vision-capable | Screenshots rejected/ignored | Document required model capability in README |
| Apple Speech on-device model not downloaded | STT fails first run | Detect + surface a clear error; macOS prompts install |

---

## 7. Test checklist (run before declaring done)

- [ ] tokenharbor + `deepseek-v4.1-flash:free`: text response streams and speaks.
- [ ] tokenharbor + screenshot: model correctly describes on-screen content.
- [ ] LM Studio (`localhost:1234`): same two checks.
- [ ] LM Studio on a LAN IP: same two checks (configurable base URL).
- [ ] `[POINT:x,y:label]` tag → cursor flies to the right spot (cloud model).
- [ ] Free STT transcribes via Apple Speech (no AssemblyAI key present).
- [ ] Free TTS plays via system voice (internet off).
- [ ] Settings persist across app restart.
- [ ] Conversation history / follow-up questions work.

---

## 8. Decisions log

| # | Decision | Value | Source |
|---|---|---|---|
| 1 | Routing location | **Both** (Worker for cloud, direct for LM Studio) | you |
| 2 | Reasoning level | **High** | you |
| 3 | Backends first | tokenharbor cloud + LM Studio | you |
| 4 | Voice | **Free** (Apple STT + system TTS) | you |
| 5 | Default cloud model | `deepseek-v4.1-flash:free` | you |
| 6 | LM Studio URL | configurable (localhost **or** LAN PC) | you |
| 7 | Signing | **ad-hoc** | you |
| 8 | Sequence | **plan doc first** (this) | you |
| 9 | Fork hosting | push to GitHub fork under `bmonekkk` | you |
| 10 | Local models to test | Qwen3.8-27B / Gemma4-26B / Gemma4-12B (speed+quality TBD) | you |
| 11 | `/models` proxy | yes — panel gets a model dropdown | you |
| 12 | Git identity | `bmonekkk <182367900+bmonekkk@users.noreply.github.com>` (never real name) | you |

---

## 9. Resolved questions

1. **Fork hosting** → push to a GitHub fork under the `bmonekkk` account.
2. **LM Studio model** → will trial `qwen3.8-27b`, `gemma4-26b`, `gemma4-12b` for
   speed/quality later. **Requirement: the local model must be vision-capable.**
   The base URL and model stay fully configurable so trials are quick.
3. **`/models` proxy** → yes, implemented in Phase 3.

### Note on commit attribution
Commits are authored as `bmonekkk <182367900+bmonekkk@users.noreply.github.com>`
(see Decisions log #12), so they link back to the GitHub account.

---

## 10. Outcome

All phases shipped on `main` (fast-forwarded from
`feature/multi-provider-free-voice`). Deviations from the original plan:

| Planned | Actually shipped |
|---|---|
| Hand-edit `.pbxproj` to register new files | **Not needed** — the project uses `PBXFileSystemSynchronizedRootGroup`, so new `.swift` files compile automatically. |
| `GET /models` Worker route | Shipped as **`GET /v1/models`** alongside `POST /v1/chat/completions`. |
| `/chat` routes by provider header | Kept the existing Anthropic `/chat`; added a separate OpenAI-compatible `/v1/chat/completions`. |
| — (not planned) | Removed the first-run intro video, welcome animation, Start button, and email gate. |
| — (not planned) | Forced STT and TTS to **English** (`en-US`). |
| — (not planned) | Added a **per-provider API key cache** so switching presets doesn't wipe a key. |
| — (not planned) | **Disabled PostHog telemetry** and removed the upstream Sparkle appcast / auto-updater wiring. |

Build/run: `scripts/build-local.sh` then `scripts/run-local.sh`.

Test status:
- ✅ tokenharbor `deepseek-v4.1-flash:free` — text + vision responses work.
- ⏳ LM Studio (`localhost` and LAN IP) — pending the user's local test.
- ⏳ End-to-end push-to-talk + cursor pointing — pending.

Known trade-offs documented in the README: API keys live in `UserDefaults`
(plaintext, local only), sandbox is disabled for ScreenCaptureKit/LAN access,
and a deployed Worker URL is usable by anyone who knows it.

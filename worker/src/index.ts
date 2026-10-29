/**
 * Clicky Proxy Worker
 *
 * Proxies requests to AI/voice providers so the app never ships raw API keys.
 * Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat                  → Anthropic Messages API (streaming)
 *   POST /v1/chat/completions   → OpenAI-compatible upstream (tokenharbor), key injected
 *   GET  /v1/models             → OpenAI-compatible upstream model list
 *   POST /tts                   → ElevenLabs TTS API
 *   POST /transcribe-token      → AssemblyAI temporary websocket token
 *
 * To use cloud models without storing a key in the app, point the app's
 * "Base URL" at "<your-worker-url>/v1" and leave the API key blank. LM Studio
 * runs on your LAN and is called directly — it never passes through this Worker.
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  TOKENHARBOR_API_KEY: string;
  TOKENHARBOR_BASE_URL?: string;
}

const DEFAULT_TOKENHARBOR_BASE_URL = "https://tokenharbor.ai/v1";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    try {
      if (request.method === "POST" && url.pathname === "/chat") {
        return await handleAnthropicChat(request, env);
      }

      if (request.method === "POST" && url.pathname === "/v1/chat/completions") {
        return await handleOpenAICompatibleChat(request, env);
      }

      if (request.method === "GET" && url.pathname === "/v1/models") {
        return await handleOpenAICompatibleModels(env);
      }

      if (request.method === "POST" && url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (request.method === "POST" && url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return jsonError(String(error), 500);
    }

    return new Response("Not found", { status: 404 });
  },
};

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/** The configured OpenAI-compatible root, with any trailing slash removed. */
function tokenHarborBaseURL(env: Env): string {
  return (env.TOKENHARBOR_BASE_URL || DEFAULT_TOKENHARBOR_BASE_URL).replace(/\/+$/, "");
}

async function handleAnthropicChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

/**
 * OpenAI-compatible chat passthrough. The app's request body is forwarded
 * verbatim, and the real provider key is injected here so it never reaches
 * the client.
 */
async function handleOpenAICompatibleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch(`${tokenHarborBaseURL(env)}/chat/completions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.TOKENHARBOR_API_KEY}`,
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/v1/chat/completions] Upstream error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

/** Returns the upstream model list so the app can offer a dropdown. */
async function handleOpenAICompatibleModels(env: Env): Promise<Response> {
  const response = await fetch(`${tokenHarborBaseURL(env)}/models`, {
    method: "GET",
    headers: {
      authorization: `Bearer ${env.TOKENHARBOR_API_KEY}`,
    },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/v1/models] Upstream error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

// Bring-your-own-key management. POST verifies a key with the provider and stores it in
// Vault; DELETE removes it. Clients read key metadata from `provider_credentials` over REST.

import { corsHeaders, preflight } from "../_shared/cors.ts";
import {
  DEFAULT_MISTRAL_API_BASE_URL,
  deleteProviderKey,
  isProvider,
  normalizeApiKey,
  type Provider,
  storeProviderKey,
  verifyMistralKey,
} from "../_shared/credentials.ts";
import { loadEnv } from "../_shared/env.ts";
import { errorResponse, HttpError, json, readJsonObject } from "../_shared/http.ts";
import { authenticate, serviceClient } from "../_shared/supabase.ts";

const env = loadEnv();
const service = serviceClient(env);
const mistralBaseUrl = Deno.env.get("MISTRAL_API_BASE_URL") || DEFAULT_MISTRAL_API_BASE_URL;

function parseProvider(body: Record<string, unknown>): Provider {
  if (!isProvider(body.provider)) {
    throw new HttpError(400, "unsupported provider", "invalid_request");
  }
  return body.provider;
}

async function saveKey(userId: string, body: Record<string, unknown>): Promise<Response> {
  const provider = parseProvider(body);
  const key = normalizeApiKey(body.api_key);

  switch (await verifyMistralKey(key, { baseUrl: mistralBaseUrl })) {
    case "invalid":
      throw new HttpError(422, "That key was rejected by Mistral.", "invalid_api_key");
    case "unavailable":
      throw new HttpError(
        503,
        "Couldn't reach Mistral to verify the key. Try again.",
        "provider_unavailable",
      );
  }
  return json(await storeProviderKey(service, userId, provider, key));
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;
  try {
    const { userId } = await authenticate(env, req);
    const body = await readJsonObject(req);
    switch (req.method) {
      case "POST":
        return await saveKey(userId, body);
      case "DELETE":
        await deleteProviderKey(service, userId, parseProvider(body));
        return new Response(null, { status: 204, headers: corsHeaders });
      default:
        throw new HttpError(405, "method not allowed");
    }
  } catch (error) {
    return errorResponse(error);
  }
});

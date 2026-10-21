// Bring-your-own-key: users' provider API keys, stored in Vault via service-role RPCs
// (migration 20261021110000_provider_credentials.sql). Keys never leave the server and
// must never be logged or echoed in errors.

import type { SupabaseClient } from "@supabase/supabase-js";
import { HttpError } from "./http.ts";

export const PROVIDERS = ["mistral"] as const;
export type Provider = (typeof PROVIDERS)[number];

export interface ProviderCredential {
  provider: Provider;
  key_hint: string;
  status: "valid" | "invalid";
  verified_at: string | null;
}

const MIN_KEY_LENGTH = 8;
const MAX_KEY_LENGTH = 200;

export function isProvider(value: unknown): value is Provider {
  return PROVIDERS.includes(value as Provider);
}

/** Trims and shape-checks a pasted key; throws 400 without echoing it. */
export function normalizeApiKey(raw: unknown): string {
  if (typeof raw !== "string") throw new HttpError(400, "api_key is required", "invalid_request");
  const key = raw.trim();
  if (key.length < MIN_KEY_LENGTH || key.length > MAX_KEY_LENGTH || /\s/.test(key)) {
    throw new HttpError(400, "That doesn't look like an API key.", "malformed_api_key");
  }
  return key;
}

export type KeyCheck = "valid" | "invalid" | "unavailable";

export interface VerifyOptions {
  baseUrl?: string;
  timeoutMs?: number;
  fetchFn?: typeof fetch;
}

export const DEFAULT_MISTRAL_API_BASE_URL = "https://api.mistral.ai";

/** Asks Mistral whether the key works (`GET /v1/models`). Network trouble is "unavailable". */
export async function verifyMistralKey(
  key: string,
  options: VerifyOptions = {},
): Promise<KeyCheck> {
  const baseUrl = (options.baseUrl ?? DEFAULT_MISTRAL_API_BASE_URL).replace(/\/+$/, "");
  const fetchFn = options.fetchFn ?? fetch;
  try {
    const response = await fetchFn(`${baseUrl}/v1/models`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(options.timeoutMs ?? 8_000),
    });
    await response.body?.cancel();
    if (response.ok) return "valid";
    if (response.status === 401 || response.status === 403) return "invalid";
    return "unavailable";
  } catch {
    return "unavailable";
  }
}

/** Shape returned to clients; mirrors the columns they can read over REST. */
export function credentialResponse(row: ProviderCredential): ProviderCredential {
  return {
    provider: row.provider,
    key_hint: row.key_hint,
    status: row.status,
    verified_at: row.verified_at,
  };
}

// RPC errors are reduced to their SQLSTATE so nothing derived from the key reaches logs.
function rpcError(name: string, error: { code?: string }): Error {
  return new Error(`${name} failed (${error.code ?? "unknown"})`);
}

export async function storeProviderKey(
  service: SupabaseClient,
  userId: string,
  provider: Provider,
  key: string,
): Promise<ProviderCredential> {
  const { data, error } = await service.rpc("set_provider_key", {
    p_user_id: userId,
    p_provider: provider,
    p_key: key,
    p_status: "valid",
  });
  if (error) throw rpcError("set_provider_key", error);
  return credentialResponse(data as ProviderCredential);
}

export async function deleteProviderKey(
  service: SupabaseClient,
  userId: string,
  provider: Provider,
): Promise<void> {
  const { error } = await service.rpc("delete_provider_key", {
    p_user_id: userId,
    p_provider: provider,
  });
  if (error) throw rpcError("delete_provider_key", error);
}

export function missingKeyError(): HttpError {
  return new HttpError(
    412,
    "Add your Mistral API key in Settings to start chatting.",
    "missing_api_key",
  );
}

/** The server-wide key, if configured. A development convenience: it is used for every user without their own key. */
function fallbackMistralKey(): string | undefined {
  return Deno.env.get("MISTRAL_API_KEY") || undefined;
}

/** Cheap existence check (no decryption) used before enqueuing work. */
export async function requireMistralKey(service: SupabaseClient, userId: string): Promise<void> {
  const { count, error } = await service
    .from("provider_credentials")
    .select("provider", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("provider", "mistral");
  if (error) throw new Error(`provider_credentials lookup failed (${error.code})`);
  if (!count && !fallbackMistralKey()) throw missingKeyError();
}

/** The key to call Mistral with on the user's behalf. */
export async function getMistralKey(service: SupabaseClient, userId: string): Promise<string> {
  const { data, error } = await service.rpc("get_provider_key", {
    p_user_id: userId,
    p_provider: "mistral",
  });
  if (error) throw rpcError("get_provider_key", error);
  const key = (data as string | null) ?? fallbackMistralKey();
  if (!key) throw missingKeyError();
  return key;
}

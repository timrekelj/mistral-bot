import { assertEquals, assertThrows } from "@std/assert";
import {
  credentialResponse,
  isProvider,
  missingKeyError,
  normalizeApiKey,
  verifyMistralKey,
} from "../_shared/credentials.ts";
import { HttpError } from "../_shared/http.ts";

const KEY = "good-key-1234";

function respondWith(status: number) {
  const calls: Request[] = [];
  const fetchFn: typeof fetch = (input, init) => {
    calls.push(new Request(input, init));
    return Promise.resolve(new Response("{}", { status }));
  };
  return { calls, fetchFn };
}

Deno.test("normalizeApiKey trims surrounding whitespace", () => {
  assertEquals(normalizeApiKey(`  ${KEY}\n`), KEY);
});

Deno.test("normalizeApiKey rejects malformed keys without echoing them", () => {
  for (const raw of ["", "   ", "short", "has inner space", "x".repeat(201), 42, undefined]) {
    const error = assertThrows(() => normalizeApiKey(raw), HttpError);
    assertEquals(error.status, 400);
    if (typeof raw === "string" && raw.trim()) {
      assertEquals(error.message.includes(raw.trim()), false);
    }
  }
});

Deno.test("isProvider accepts only known providers", () => {
  assertEquals(isProvider("mistral"), true);
  assertEquals(isProvider("openai"), false);
  assertEquals(isProvider(undefined), false);
});

Deno.test("verifyMistralKey: 200 is valid and sends the key as a bearer", async () => {
  const { calls, fetchFn } = respondWith(200);
  assertEquals(await verifyMistralKey(KEY, { baseUrl: "http://stub/", fetchFn }), "valid");
  assertEquals(calls[0].url, "http://stub/v1/models");
  assertEquals(calls[0].method, "GET");
  assertEquals(calls[0].headers.get("Authorization"), `Bearer ${KEY}`);
});

Deno.test("verifyMistralKey: 401 and 403 are invalid", async () => {
  assertEquals(await verifyMistralKey(KEY, { fetchFn: respondWith(401).fetchFn }), "invalid");
  assertEquals(await verifyMistralKey(KEY, { fetchFn: respondWith(403).fetchFn }), "invalid");
});

Deno.test("verifyMistralKey: 5xx and 429 are unavailable", async () => {
  assertEquals(await verifyMistralKey(KEY, { fetchFn: respondWith(500).fetchFn }), "unavailable");
  assertEquals(await verifyMistralKey(KEY, { fetchFn: respondWith(429).fetchFn }), "unavailable");
});

Deno.test("verifyMistralKey: network errors are unavailable", async () => {
  const fetchFn: typeof fetch = () => Promise.reject(new TypeError("connection refused"));
  assertEquals(await verifyMistralKey(KEY, { fetchFn }), "unavailable");
});

Deno.test("verifyMistralKey: a hung request times out as unavailable", async () => {
  const fetchFn: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) =>
      init?.signal?.addEventListener("abort", () => reject(init.signal?.reason))
    );
  assertEquals(await verifyMistralKey(KEY, { fetchFn, timeoutMs: 10 }), "unavailable");
});

Deno.test("credentialResponse exposes only display metadata", () => {
  const row = {
    user_id: "u",
    provider: "mistral" as const,
    vault_secret_id: "secret-id",
    key_hint: "…1234",
    status: "valid" as const,
    verified_at: "2026-10-21T10:00:00Z",
  };
  assertEquals(credentialResponse(row), {
    provider: "mistral",
    key_hint: "…1234",
    status: "valid",
    verified_at: "2026-10-21T10:00:00Z",
  });
});

Deno.test("missingKeyError is a 412 with a machine code", () => {
  const error = missingKeyError();
  assertEquals([error.status, error.code], [412, "missing_api_key"]);
});

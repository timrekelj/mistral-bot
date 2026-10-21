import { assert, assertEquals, assertFalse } from "@std/assert";
import { bearerToken, isServiceRequest, timingSafeEqual } from "../_shared/auth.ts";

const KEY = "service-role-key";

function request(authorization?: string): Request {
  const headers = authorization ? { Authorization: authorization } : undefined;
  return new Request("http://localhost/agent-step", { method: "POST", headers });
}

Deno.test("bearerToken extracts the token", () => {
  assertEquals(bearerToken(request(`Bearer ${KEY}`)), KEY);
  assertEquals(bearerToken(request(`bearer ${KEY}`)), KEY);
  assertEquals(bearerToken(request(KEY)), null);
  assertEquals(bearerToken(request()), null);
});

Deno.test("isServiceRequest accepts only the exact service key", () => {
  assert(isServiceRequest(request(`Bearer ${KEY}`), KEY));
  assertFalse(isServiceRequest(request(`Bearer ${KEY}x`), KEY));
  assertFalse(isServiceRequest(request(`Bearer ${KEY.slice(0, -1)}`), KEY));
  assertFalse(isServiceRequest(request("Bearer user-jwt"), KEY));
  assertFalse(isServiceRequest(request(), KEY));
});

Deno.test("isServiceRequest rejects everything when the key is unset", () => {
  assertFalse(isServiceRequest(request("Bearer "), ""));
  assertFalse(isServiceRequest(request("Bearer x"), ""));
});

Deno.test("timingSafeEqual compares content and length", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "abcd"));
  assertFalse(timingSafeEqual("", "a"));
  assert(timingSafeEqual("", ""));
});

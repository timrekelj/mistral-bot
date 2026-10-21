import { assertEquals } from "@std/assert";
import { errorResponse, HttpError } from "../_shared/http.ts";

Deno.test("errorResponse includes the machine code when set", async () => {
  const response = errorResponse(
    new HttpError(422, "That key was rejected by Mistral.", "invalid_api_key"),
  );
  assertEquals(response.status, 422);
  assertEquals(await response.json(), {
    error: "That key was rejected by Mistral.",
    code: "invalid_api_key",
  });
});

Deno.test("errorResponse omits code when absent", async () => {
  const response = errorResponse(new HttpError(400, "text is required"));
  assertEquals(await response.json(), { error: "text is required" });
});

Deno.test("unexpected errors become an opaque 500", async () => {
  const log = console.error;
  console.error = () => {};
  try {
    const response = errorResponse(new Error("secret detail"));
    assertEquals(response.status, 500);
    assertEquals(await response.json(), { error: "internal error" });
  } finally {
    console.error = log;
  }
});

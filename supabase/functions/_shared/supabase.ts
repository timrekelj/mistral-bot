import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Env } from "./env.ts";

const serverAuth = { persistSession: false, autoRefreshToken: false } as const;

/** Bypasses RLS. Only for runtime writes the user may not perform themselves. */
export function serviceClient(env: Env): SupabaseClient {
  return createClient(env.supabaseUrl, env.serviceRoleKey, { auth: serverAuth });
}

/** Acts as the calling user, so every query is subject to RLS. */
export function userClient(env: Env, authorization: string): SupabaseClient {
  return createClient(env.supabaseUrl, env.anonKey, {
    auth: serverAuth,
    global: { headers: { Authorization: authorization } },
  });
}

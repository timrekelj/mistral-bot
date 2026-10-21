import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { bearerToken } from "./auth.ts";
import type { Env } from "./env.ts";
import { HttpError } from "./http.ts";

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

export interface AuthenticatedUser {
  userId: string;
  /** RLS-scoped client acting as the user. */
  db: SupabaseClient;
}

/** Resolves the calling user from the request's JWT, or throws 401. */
export async function authenticate(env: Env, req: Request): Promise<AuthenticatedUser> {
  const token = bearerToken(req);
  if (!token) throw new HttpError(401, "unauthorized");
  const db = userClient(env, `Bearer ${token}`);
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "unauthorized");
  return { userId: data.user.id, db };
}

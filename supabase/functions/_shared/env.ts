export interface Env {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

/** Variables injected by the Supabase Edge Runtime (and `supabase functions serve`). */
export function loadEnv(): Env {
  return {
    supabaseUrl: requireEnv("SUPABASE_URL"),
    anonKey: requireEnv("SUPABASE_ANON_KEY"),
    serviceRoleKey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  };
}

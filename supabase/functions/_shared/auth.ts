export function bearerToken(req: Request): string | null {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] ?? null;
}

/** True when the request carries the service-role key (used by pg_net kicks). */
export function isServiceRequest(req: Request, serviceRoleKey: string): boolean {
  const token = bearerToken(req);
  return token !== null && serviceRoleKey.length > 0 && timingSafeEqual(token, serviceRoleKey);
}

export function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ (right[i % right.length] ?? 0);
  return diff === 0;
}

// Accepts a user message and enqueues an agent run for it. Requires a user JWT.

import type { SupabaseClient } from "@supabase/supabase-js";
import { preflight } from "../_shared/cors.ts";
import { loadEnv } from "../_shared/env.ts";
import { errorResponse, HttpError, isUuid, json, readJsonObject } from "../_shared/http.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";

const MAX_TEXT_LENGTH = 32_000;

const env = loadEnv();
const service = serviceClient(env);

interface ChatSendRequest {
  conversationId?: string;
  agentId?: string;
  text: string;
}

function parseRequest(body: Record<string, unknown>): ChatSendRequest {
  const { conversation_id: conversationId, agent_id: agentId, text } = body;
  if (conversationId !== undefined && !isUuid(conversationId)) {
    throw new HttpError(400, "conversation_id must be a uuid");
  }
  if (agentId !== undefined && !isUuid(agentId)) {
    throw new HttpError(400, "agent_id must be a uuid");
  }
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new HttpError(400, "text is required");
  }
  if (text.length > MAX_TEXT_LENGTH) throw new HttpError(413, "text is too long");
  return { conversationId, agentId, text };
}

/** Resolves (or creates) the conversation through RLS, so ownership is enforced by Postgres. */
async function resolveConversation(
  db: SupabaseClient,
  userId: string,
  req: ChatSendRequest,
): Promise<{ id: string; agentId: string }> {
  if (req.conversationId) {
    const { data, error } = await db
      .from("conversations")
      .select("id, agent_id")
      .eq("id", req.conversationId)
      .maybeSingle();
    if (error) throw new Error(`load conversation: ${error.message}`);
    if (!data) throw new HttpError(404, "conversation not found");
    const agentId = req.agentId ?? data.agent_id;
    if (!agentId) throw new HttpError(409, "conversation has no agent; pass agent_id");
    return { id: data.id, agentId };
  }

  const agentQuery = db.from("agents").select("id").eq("is_active", true);
  const { data: agent, error: agentError } =
    await (req.agentId ? agentQuery.eq("id", req.agentId) : agentQuery.eq("role", "main"))
      .maybeSingle();
  if (agentError) throw new Error(`load agent: ${agentError.message}`);
  if (!agent) throw new HttpError(404, "agent not found");

  const { data, error } = await db
    .from("conversations")
    .insert({ user_id: userId, agent_id: agent.id, source: "chat" })
    .select("id")
    .single();
  if (error) throw new Error(`create conversation: ${error.message}`);
  return { id: data.id, agentId: agent.id };
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;
  try {
    if (req.method !== "POST") throw new HttpError(405, "method not allowed");
    const authorization = req.headers.get("Authorization");
    if (!authorization) throw new HttpError(401, "unauthorized");

    const db = userClient(env, authorization);
    const { data: auth, error: authError } = await db.auth.getUser(
      authorization.replace(/^Bearer\s+/i, ""),
    );
    if (authError || !auth.user) throw new HttpError(401, "unauthorized");
    const userId = auth.user.id;

    const request = parseRequest(await readJsonObject(req));
    const conversation = await resolveConversation(db, userId, request);

    const { data: message, error: messageError } = await db
      .from("messages")
      .insert({
        conversation_id: conversation.id,
        user_id: userId,
        role: "user",
        content: [{ type: "text", text: request.text }],
      })
      .select("id")
      .single();
    if (messageError) throw new Error(`insert message: ${messageError.message}`);

    // Runs are runtime state that users cannot write; inserting as `ready` fires the kick.
    const { data: run, error: runError } = await service
      .from("agent_runs")
      .insert({
        user_id: userId,
        agent_id: conversation.agentId,
        conversation_id: conversation.id,
        status: "ready",
        next_input: { text: request.text, message_id: message.id, target_steps: 1 },
      })
      .select("id")
      .single();
    if (runError) throw new Error(`enqueue run: ${runError.message}`);

    return json({ conversation_id: conversation.id, message_id: message.id, run_id: run.id });
  } catch (error) {
    return errorResponse(error);
  }
});

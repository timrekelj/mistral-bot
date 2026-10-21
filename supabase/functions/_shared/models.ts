// Model IDs and Mistral list prices (USD, October 2026; previews, subject to change).
// See docs/PLAN.md section 7.1. Keep every model reference going through this file.

export type ModelTier = "large" | "small";

export interface ChatModel {
  id: string;
  inputPerMTokens: number;
  cachedInputPerMTokens: number;
  outputPerMTokens: number;
}

export const CHAT_MODELS: Record<ModelTier, ChatModel> = {
  large: {
    id: "mistral-large-4",
    inputPerMTokens: 1.36,
    cachedInputPerMTokens: 0.14,
    outputPerMTokens: 4.18,
  },
  small: {
    id: "mistral-small-4",
    inputPerMTokens: 0.15,
    // No published cached rate for Small 4; bill cached tokens as regular input.
    cachedInputPerMTokens: 0.15,
    outputPerMTokens: 0.6,
  },
};

export const SPEECH_MODELS = {
  transcribeRealtime: { id: "voxtral-mini-transcribe-realtime-3-0", perAudioMinute: 0.008 },
  tts: { id: "voxtral-mini-tts-3-0", perMCharacters: 13 },
} as const;

export const TOOL_PRICES = {
  webSearchPerCall: 0.03,
  codeInterpreterPerCall: 0.03,
  imageGenerationPerImage: 0.1,
} as const;

export const BATCH_DISCOUNT = 0.5;

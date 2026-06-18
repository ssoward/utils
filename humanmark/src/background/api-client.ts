import type { BlockResult } from "../shared/types";

export interface APIAdapter {
  name: string;
  maxChars: number;
  requestsPerMin: number;
  analyze(text: string, apiKey: string): Promise<number>;
}

// GPTZero — free tier: 10k words/month; score field: completely_generated_prob
export const GPTZeroAdapter: APIAdapter = {
  name: "gptzero",
  maxChars: 50_000,
  requestsPerMin: 10,
  async analyze(text, apiKey) {
    const res = await fetch("https://api.gptzero.me/v2/predict/text", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
      },
      body: JSON.stringify({ document: text }),
    });
    if (!res.ok) throw new Error(`GPTZero error ${res.status}`);
    const data = await res.json() as { documents: Array<{ completely_generated_prob: number }> };
    return data.documents[0]?.completely_generated_prob ?? 0;
  },
};

// Sapling — $0.002/1k chars; score is direct 0-1 probability
export const SaplingAdapter: APIAdapter = {
  name: "sapling",
  maxChars: 2_000,
  requestsPerMin: 60,
  async analyze(text, apiKey) {
    const res = await fetch("https://api.sapling.ai/api/v1/aidetect", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: apiKey, text }),
    });
    if (!res.ok) throw new Error(`Sapling error ${res.status}`);
    const data = await res.json() as { score: number };
    return data.score;
  },
};

export const ADAPTERS: Record<string, APIAdapter> = {
  gptzero: GPTZeroAdapter,
  sapling: SaplingAdapter,
};

// Fast heuristic fallback — no network, ~0ms, ~80% accuracy
// Signals: sentence length variance (burstiness), type-token ratio, avg word length
export function heuristicScore(text: string): number {
  const sentences = text.match(/[^.!?]+[.!?]+/g) ?? [text];
  // Single-sentence/short-fragment input — too little signal to flag.
  if (sentences.length < 2) return 0.3;

  const lengths = sentences.map((s) => s.trim().split(/\s+/).length);
  const mean = lengths.reduce((a, b) => a + b, 0) / lengths.length;
  const variance =
    lengths.reduce((sum, l) => sum + (l - mean) ** 2, 0) / lengths.length;
  // AI text: low variance in sentence length (flat burstiness)
  const burstinessScore = Math.max(0, 1 - variance / 30);

  const words = text.toLowerCase().match(/\b[a-z]+\b/g) ?? [];
  const uniqueWords = new Set(words);
  // AI text: higher type-token ratio (more varied vocabulary)
  const ttrScore = words.length > 0 ? uniqueWords.size / words.length : 0.5;
  // TTR inversion: high TTR paradoxically indicates AI in short texts
  const ttrAdjusted = ttrScore > 0.7 ? ttrScore * 0.6 : (1 - ttrScore) * 0.4;

  // Punctuation uniformity — AI rarely uses em-dashes, ellipses, or parenthetical asides
  const hasRichPunctuation = /[—…();\[\]]/.test(text);
  const punctBonus = hasRichPunctuation ? -0.1 : 0.05;

  let score = burstinessScore * 0.6 + ttrAdjusted * 0.4 + punctBonus;

  // Confidence dampener for short text. With only 2 short sentences,
  // burstiness/TTR signals are mathematically low/high regardless of source
  // (form labels, error messages, captions all over-fire). Require 3+
  // sentences AND 30+ words for a flag-worthy score; otherwise cap below
  // the uncertain threshold so we don't paint UI copy red.
  if (sentences.length < 3 || words.length < 30) {
    score = Math.min(score, 0.45);
  }

  return Math.min(1, Math.max(0, score));
}

export function buildResult(
  hash: string,
  score: number,
  source: BlockResult["source"],
  provider?: string
): BlockResult {
  return { hash, score, source, provider, analyzedAt: Date.now() };
}

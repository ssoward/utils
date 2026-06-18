// Twitter/X — tweet text blocks within article elements
export const TwitterAdapter = {
  hostname: "twitter.com",
  textBlockSelector: 'article[data-testid="tweet"] div[data-testid="tweetText"]',
  scrollSentinelSelector: 'div[data-testid="cellInnerDiv"]:last-child',
  // AI tweets often have zero typos, uniform sentence length, no emoji-as-emphasis
  postProcessScore(score: number, text: string): number {
    const emojiDensity = (text.match(/\p{Emoji}/gu) ?? []).length / text.length;
    // High emoji density suggests human expression; lower the score slightly
    if (emojiDensity > 0.05) return Math.max(0, score - 0.05);
    // Very clean text with no contractions — bump score
    if (!/\b(don't|can't|won't|I'm|it's|that's)\b/i.test(text)) return Math.min(1, score + 0.06);
    return score;
  },
};

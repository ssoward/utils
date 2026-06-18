// LinkedIn — post body and comment text
export const LinkedInAdapter = {
  hostname: "linkedin.com",
  textBlockSelector: "div.feed-shared-update-v2__description span.break-words, div.comments-list .comment-text",
  scrollSentinelSelector: "div.scaffold-finite-scroll__load-button",
  // AI LinkedIn posts often follow "3 bullet points + closing CTA" structure
  postProcessScore(score: number, text: string): number {
    const lines = text.split("\n").filter((l) => l.trim().length > 0);
    // Three short consecutive lines followed by a call-to-action is a strong AI signal
    const shortLineRun = lines.filter((l) => l.split(" ").length < 12).length;
    if (shortLineRun >= 3 && /\b(follow|connect|share|comment|thoughts\?|dm me)\b/i.test(text)) {
      return Math.min(1, score + 0.12);
    }
    return score;
  },
};

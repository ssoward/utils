// Strava — activity descriptions and club post comments
// AI fitness writing tends to use generic motivational phrases
const AI_FITNESS_PHRASES = [
  "pushed myself",
  "every mile counts",
  "embracing the journey",
  "mental strength",
  "the grind",
  "fuel your",
  "recovery is key",
  "consistency is everything",
  "one step at a time",
  "trust the process",
  "stay the course",
  "dig deep",
  "gave it my all",
  "personal best",
  "feeling strong today",
  "body and mind",
  "push your limits",
  "earned it",
  "sweat is",
  "no excuses",
];

export const StravaAdapter = {
  hostname: "strava.com",
  textBlockSelector: "div.activity-description, div.comment-text",
  scrollSentinelSelector: "button[data-testid='load-more']",
  postProcessScore(score: number, text: string): number {
    const lower = text.toLowerCase();
    const matchCount = AI_FITNESS_PHRASES.filter((p) => lower.includes(p)).length;
    const bump = Math.min(0.20, matchCount * 0.05);
    return Math.min(1, score + bump);
  },
};

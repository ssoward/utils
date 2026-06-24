// 64-bit composite hash: two FNV-1a passes with different seeds plus the text
// length. Pure JS (no SubtleCrypto needed in synchronous paths) and small
// enough to keep cache keys short while making accidental collisions
// vanishingly unlikely for the volumes we cache.
export function hashText(text: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0xcbf29ce4;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 ^= c;
    h1 = (h1 * 0x01000193) >>> 0;
    h2 ^= c + i; // position-aware second pass
    h2 = (h2 * 0x100000001b3) >>> 0;
  }
  const lenTag = text.length.toString(36);
  return `${h1.toString(16).padStart(8, "0")}${h2.toString(16).padStart(8, "0")}${lenTag}`;
}

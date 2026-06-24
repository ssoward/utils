import type { Settings, MessageRequest, MessageResponse } from "../shared/types";
import { hashText } from "../shared/text-hasher";
import { BATCH_SIZE } from "../shared/constants";
import { extractText } from "./block-eligibility";
import { applyState, applyResult, isPaused } from "./renderer";

interface QueueEntry {
  el: HTMLElement;
  priority: number; // 1 = visible, 0 = offscreen
}

const queue: Map<string, QueueEntry> = new Map();
let processing = false;
let active: Settings | null = null;
let postProcess: ((score: number, text: string) => number) | null = null;

export function setActiveSettings(s: Settings): void { active = s; }
export function setPostProcessor(fn: ((score: number, text: string) => number) | null): void {
  postProcess = fn;
}

const io = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    const el = entry.target as HTMLElement;
    const nodeId = el.dataset.hmId;
    if (nodeId && queue.has(nodeId)) {
      queue.get(nodeId)!.priority = entry.isIntersecting ? 1 : 0;
    }
  }
}, { threshold: 0 });

export function enqueue(el: HTMLElement): void {
  if (el.dataset.hmState === "done" || el.dataset.hmState === "analyzing") return;

  if (!el.dataset.hmId) {
    el.dataset.hmId = `hm-${Math.random().toString(36).slice(2, 10)}`;
  }
  const nodeId = el.dataset.hmId;

  el.dataset.hmState = "pending";
  io.observe(el);
  queue.set(nodeId, { el, priority: 0 });

  scheduleFlush();
}

function scheduleFlush(): void {
  setTimeout(flush, 300);
}

async function flush(): Promise<void> {
  if (queue.size === 0) return;
  if (processing) return;

  if (isPaused() || !active) {
    setTimeout(flush, 1000);
    return;
  }

  processing = true;

  const sorted = [...queue.entries()].sort((a, b) => b[1].priority - a[1].priority);
  const batch = sorted.slice(0, BATCH_SIZE);
  const settings = active;

  for (const [nodeId, entry] of batch) {
    queue.delete(nodeId);
    io.unobserve(entry.el);

    // Element may have been detached between enqueue and flush
    if (!entry.el.isConnected) continue;

    const text = extractText(entry.el);
    const hash = hashText(text);
    applyState(nodeId, "analyzing");

    const msg: MessageRequest = {
      type: "ANALYZE_BLOCK",
      payload: { hash, text, nodeId },
    };

    chrome.runtime.sendMessage(msg, (resp: MessageResponse | undefined) => {
      if (chrome.runtime.lastError || !resp) {
        applyState(nodeId, "error");
        return;
      }
      if (resp.type === "BLOCK_RESULT") {
        if (postProcess) {
          resp.result.score = Math.min(1, Math.max(0, postProcess(resp.result.score, text)));
        }
        applyResult(nodeId, resp.result, settings);
      } else {
        applyState(nodeId, "skipped");
      }
    });
  }

  processing = false;
  if (queue.size > 0) setTimeout(flush, 400);
}

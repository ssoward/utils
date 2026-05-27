import { createServer } from "http";
import { readFile } from "fs/promises";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { spawn } from "child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = 3900;

// ---------- Harness Core: The middleware between user and AI ----------

class AIHarness {
  constructor() {
    this.sessions = new Map();     // Session state management
    this.middleware = [];           // Pre/post processing pipeline
    this.tools = new Map();        // Registered tools the AI can use
    this.metrics = { requests: 0, tokens: 0, errors: 0, avgLatency: 0 };
  }

  // Register middleware that transforms requests/responses
  use(fn) {
    this.middleware.push(fn);
  }

  // Register a tool the AI can invoke
  registerTool(name, description, handler) {
    this.tools.set(name, { name, description, handler });
  }

  // Get or create a session (conversation memory)
  getSession(sessionId) {
    if (!this.sessions.has(sessionId)) {
      this.sessions.set(sessionId, {
        id: sessionId,
        history: [],
        context: {},
        createdAt: Date.now(),
      });
    }
    return this.sessions.get(sessionId);
  }

  // The main execution pipeline
  async execute(sessionId, userMessage) {
    const start = Date.now();
    this.metrics.requests++;

    const session = this.getSession(sessionId);
    session.history.push({ role: "user", content: userMessage });

    // Build the request context
    let context = {
      sessionId,
      userMessage,
      history: session.history,
      systemPrompt: this.buildSystemPrompt(),
      tools: [...this.tools.keys()],
      metadata: { timestamp: Date.now() },
    };

    // Run pre-processing middleware
    const trace = [];
    for (const mw of this.middleware) {
      const before = JSON.stringify(context.userMessage);
      context = await mw(context, "pre");
      if (before !== JSON.stringify(context.userMessage)) {
        trace.push({ stage: mw.name || "middleware", action: "transformed input" });
      }
    }

    // Execute the AI call (Claude CLI or simulated)
    let response;
    try {
      response = await this.callAI(context);
    } catch (err) {
      this.metrics.errors++;
      response = { text: `Error: ${err.message}`, error: true };
    }

    // Check if AI wants to use a tool
    const toolCall = this.parseToolCall(response.text);
    if (toolCall && this.tools.has(toolCall.name)) {
      trace.push({ stage: "tool-use", action: `called ${toolCall.name}(${JSON.stringify(toolCall.args)})` });
      const toolResult = await this.tools.get(toolCall.name).handler(toolCall.args);
      // Feed tool result back to AI for final response
      context.userMessage = `Tool "${toolCall.name}" returned: ${JSON.stringify(toolResult)}\n\nUsing that result, answer the original question: ${userMessage}`;
      context.history = [...session.history];
      response = await this.callAI(context);
    }

    // Run post-processing middleware
    let result = { text: response.text };
    for (const mw of this.middleware) {
      const beforePost = result.text;
      const postResult = await mw({ ...context, response: result }, "post");
      if (postResult?.response) result = postResult.response;
      if (beforePost !== result.text) {
        trace.push({ stage: mw.name || "middleware", action: "transformed output" });
      }
    }

    session.history.push({ role: "assistant", content: result.text });

    const latency = Date.now() - start;
    this.metrics.avgLatency = Math.round(
      (this.metrics.avgLatency * (this.metrics.requests - 1) + latency) / this.metrics.requests
    );

    return {
      response: result.text,
      sessionId,
      trace,
      metrics: { latency, historyLength: session.history.length },
    };
  }

  buildSystemPrompt() {
    const toolDescs = [...this.tools.entries()]
      .map(([name, t]) => `- ${name}: ${t.description}`)
      .join("\n");
    return [
      "You are a helpful assistant running inside an AI harness demo.",
      "You demonstrate how AI harnesses work by being the AI that the harness orchestrates.",
      toolDescs ? `\nAvailable tools (use format "TOOL_CALL:name:args"):\n${toolDescs}` : "",
      "\nKeep responses concise.",
    ].join("\n");
  }

  parseToolCall(text) {
    const match = text?.match(/TOOL_CALL:(\w+):(.*)/);
    if (match) return { name: match[1], args: match[2].trim() };
    return null;
  }

  async callAI(context) {
    // Try real Claude CLI first, fall back to simulation
    try {
      return await this.callClaude(context);
    } catch {
      return this.simulateAI(context);
    }
  }

  callClaude(context) {
    return new Promise((resolve, reject) => {
      const prompt = [
        context.systemPrompt,
        "",
        ...context.history.slice(-6).map(
          (m) => `${m.role === "user" ? "Human" : "Assistant"}: ${m.content}`
        ),
        `Human: ${context.userMessage}`,
      ].join("\n");

      const child = spawn("claude", ["-p", "--output-format", "text"], {
        stdio: ["pipe", "pipe", "pipe"],
        timeout: 30000,
      });

      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (d) => (stdout += d));
      child.stderr.on("data", (d) => (stderr += d));
      child.stdin.write(prompt);
      child.stdin.end();

      child.on("close", (code) => {
        if (code === 0 && stdout.trim()) resolve({ text: stdout.trim() });
        else reject(new Error(stderr || "Claude CLI not available"));
      });
      child.on("error", () => reject(new Error("Claude CLI not found")));
    });
  }

  simulateAI(context) {
    const msg = context.userMessage.toLowerCase();

    // Simulate tool use
    if (msg.includes("time") || msg.includes("date")) {
      return { text: `TOOL_CALL:clock:now` };
    }
    if (msg.includes("calculate") || msg.includes("math")) {
      const nums = msg.match(/\d+/g);
      if (nums) return { text: `TOOL_CALL:calculator:${nums.join("+")}` };
    }
    if (msg.includes("weather")) {
      return { text: `TOOL_CALL:weather:current` };
    }

    // Simulated conversational responses
    const responses = {
      hello: "Hello! I'm running inside an AI harness. The harness manages my sessions, processes my inputs through middleware, and gives me access to tools. Ask me anything!",
      harness: "An AI harness is the orchestration layer between users and an AI model. It handles: (1) Session management - keeping conversation history, (2) Middleware pipeline - transforming inputs/outputs, (3) Tool integration - giving the AI capabilities beyond text, (4) Error handling & retries, (5) Metrics & observability. Think of it like Express.js but for AI interactions instead of HTTP requests.",
      middleware: "Middleware in an AI harness works like Express middleware. Each function can transform the request before it reaches the AI, or transform the response before it reaches the user. Examples: content filtering, prompt injection detection, response formatting, rate limiting, logging.",
      tools: "Tools extend what the AI can do beyond generating text. The harness registers tools (like 'clock', 'calculator', 'weather') and when the AI decides to use one, the harness executes it and feeds the result back. This is the core of function-calling / tool-use patterns.",
      session: "Sessions give the AI memory. Without the harness managing sessions, every message would be stateless. The harness stores conversation history, user preferences, and context - then includes relevant history in each AI call.",
      architecture: "The architecture is: User → Interface Layer → Middleware Pipeline → AI Engine → Tool Executor → Middleware Pipeline → Response. Your slack-bot, chromeCC, and brp projects each implement this pattern differently. slack-bot uses Slack as the interface, chromeCC uses a Chrome side panel, and brp would use a macOS menu bar.",
    };

    for (const [key, resp] of Object.entries(responses)) {
      if (msg.includes(key)) return { text: resp };
    }

    const historyLen = context.history.length;
    return {
      text: `I'm the AI inside the harness. You've sent ${historyLen} messages in this session. The harness tracked all of them, ran ${context.tools.length} registered tools through its pipeline, and applied middleware to this response. Try asking about "harness", "middleware", "tools", "sessions", or "architecture" to learn more. Or ask about the "time", "weather", or to "calculate" something to see tool use in action.`,
    };
  }

  getStatus() {
    return {
      sessions: this.sessions.size,
      tools: [...this.tools.keys()],
      middleware: this.middleware.map((m) => m.name || "anonymous"),
      metrics: this.metrics,
    };
  }
}

// ---------- Create and configure the harness ----------

const harness = new AIHarness();

// Middleware: logging
const loggingMiddleware = function loggingMiddleware(ctx, phase) {
  if (phase === "pre") {
    console.log(`[${new Date().toISOString()}] Session ${ctx.sessionId}: "${ctx.userMessage.slice(0, 80)}"`);
  }
  return ctx;
};
harness.use(loggingMiddleware);

// Middleware: input sanitization
const sanitizationMiddleware = function sanitizationMiddleware(ctx, phase) {
  if (phase === "pre") {
    ctx.userMessage = ctx.userMessage.replace(/<script[^>]*>.*?<\/script>/gi, "[removed]");
    ctx.metadata = { ...ctx.metadata, sanitized: true };
  }
  return ctx;
};
harness.use(sanitizationMiddleware);

// Middleware: response formatting
const formattingMiddleware = function formattingMiddleware(ctx, phase) {
  if (phase === "post" && ctx.response) {
    // Ensure response doesn't exceed reasonable length
    if (ctx.response.text.length > 2000) {
      ctx.response.text = ctx.response.text.slice(0, 2000) + "...";
    }
  }
  return ctx;
};
harness.use(formattingMiddleware);

// Register tools
harness.registerTool("clock", "Returns the current date and time", () => ({
  time: new Date().toLocaleTimeString(),
  date: new Date().toLocaleDateString(),
  iso: new Date().toISOString(),
}));

harness.registerTool("calculator", "Evaluates a math expression", (expr) => {
  const nums = String(expr).match(/[\d.]+/g)?.map(Number) || [];
  return { expression: expr, result: nums.reduce((a, b) => a + b, 0) };
});

harness.registerTool("weather", "Returns current weather (simulated)", () => ({
  temp: "72°F",
  condition: "Sunny",
  humidity: "45%",
  note: "Simulated data - a real harness would call a weather API",
}));

// ---------- HTTP Server ----------

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // CORS
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.writeHead(204); res.end(); return; }

  // Serve the frontend
  if (url.pathname === "/" || url.pathname === "/index.html") {
    const html = await readFile(join(__dirname, "index.html"), "utf-8");
    res.writeHead(200, { "Content-Type": "text/html" });
    res.end(html);
    return;
  }

  // API: Send a message through the harness
  if (url.pathname === "/api/chat" && req.method === "POST") {
    let body = "";
    for await (const chunk of req) body += chunk;
    const { message, sessionId } = JSON.parse(body);
    const result = await harness.execute(sessionId || "default", message);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(result));
    return;
  }

  // API: Get harness status
  if (url.pathname === "/api/status") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(harness.getStatus()));
    return;
  }

  // API: Get session history
  if (url.pathname === "/api/sessions") {
    const sessions = [...harness.sessions.entries()].map(([id, s]) => ({
      id,
      messageCount: s.history.length,
      createdAt: s.createdAt,
    }));
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(sessions));
    return;
  }

  // API: Architecture diagram data
  if (url.pathname === "/api/architecture") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      layers: [
        { id: "user", label: "User Interface", description: "Web UI, Slack, Chrome Extension, CLI", color: "#3b82f6" },
        { id: "middleware-pre", label: "Pre-Processing Middleware", description: "Sanitization, rate limiting, prompt injection detection", color: "#8b5cf6" },
        { id: "session", label: "Session Manager", description: "Conversation history, user context, state persistence", color: "#06b6d4" },
        { id: "ai", label: "AI Engine", description: "Claude CLI, API calls, model selection, prompt construction", color: "#f59e0b" },
        { id: "tools", label: "Tool Executor", description: "Function calling, external APIs, file operations", color: "#10b981" },
        { id: "middleware-post", label: "Post-Processing Middleware", description: "Response formatting, content filtering, metrics", color: "#8b5cf6" },
        { id: "response", label: "Response Delivery", description: "Streaming, webhooks, Slack threads, WebSocket", color: "#3b82f6" },
      ],
      connections: [
        { from: "user", to: "middleware-pre" },
        { from: "middleware-pre", to: "session" },
        { from: "session", to: "ai" },
        { from: "ai", to: "tools", label: "tool calls" },
        { from: "tools", to: "ai", label: "results" },
        { from: "ai", to: "middleware-post" },
        { from: "middleware-post", to: "response" },
      ],
      examples: [
        { name: "slack-bot", interface: "Slack Socket Mode", session: "JSON files per thread", ai: "claude -p CLI", tools: "Bash, Read, Write, Edit" },
        { name: "chromeCC", interface: "Chrome Side Panel", session: "In-memory per tab", ai: "claude -p via Native Messaging", tools: "Page context extraction" },
        { name: "brp", interface: "macOS Menu Bar", session: "UserDefaults", ai: "Planned Phase 2", tools: "Calendar, Email, Notifications" },
      ],
    }));
    return;
  }

  res.writeHead(404);
  res.end("Not found");
});

server.listen(PORT, () => {
  console.log(`\n  AI Harness Demo running at http://localhost:${PORT}\n`);
  console.log(`  Harness status:`);
  console.log(`    Middleware: ${harness.middleware.map(m => m.name).join(", ")}`);
  console.log(`    Tools: ${[...harness.tools.keys()].join(", ")}`);
  console.log(`    Claude CLI: attempting real AI, falling back to simulation\n`);
});

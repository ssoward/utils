/**
 * Returns the complete HTML for the Slack Bot dashboard.
 * Single-page app with four panels: system status, sessions, chat, message history.
 */
export function getDashboardHtml(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Slack Bot Dashboard</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Consolas', monospace;
    background: #0d1117; color: #c9d1d9; font-size: 14px;
    min-height: 100vh;
  }
  header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 12px 20px; background: #161b22; border-bottom: 1px solid #30363d;
  }
  header h1 { font-size: 16px; font-weight: 600; color: #f0f6fc; }
  .conn-badge {
    display: flex; align-items: center; gap: 6px;
    font-size: 12px; padding: 4px 10px; border-radius: 12px;
    background: #1c2128; border: 1px solid #30363d;
  }
  .conn-dot { width: 8px; height: 8px; border-radius: 50%; }
  .conn-dot.connected { background: #3fb950; box-shadow: 0 0 6px #3fb950; }
  .conn-dot.disconnected { background: #f85149; }

  .grid {
    display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: auto 1fr;
    gap: 1px; background: #30363d; height: calc(100vh - 49px);
  }
  .panel {
    background: #0d1117; display: flex; flex-direction: column; overflow: hidden;
  }
  .panel-header {
    padding: 10px 14px; font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: 1px; color: #8b949e;
    background: #161b22; border-bottom: 1px solid #30363d;
    flex-shrink: 0;
  }
  .panel-body { padding: 12px 14px; overflow-y: auto; flex: 1; }

  /* System Status */
  .metric { margin-bottom: 12px; }
  .metric-label {
    display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 4px;
  }
  .metric-label span:first-child { color: #8b949e; }
  .metric-label span:last-child { color: #f0f6fc; font-weight: 600; }
  .bar-bg {
    height: 8px; background: #21262d; border-radius: 4px; overflow: hidden;
  }
  .bar-fill {
    height: 100%; border-radius: 4px; transition: width 0.5s ease;
  }
  .bar-green { background: #3fb950; }
  .bar-yellow { background: #d29922; }
  .bar-red { background: #f85149; }
  .meta-info { font-size: 11px; color: #484f58; margin-top: 8px; }

  /* Sessions */
  .session-row {
    display: flex; justify-content: space-between; align-items: center;
    padding: 6px 0; border-bottom: 1px solid #21262d; font-size: 13px;
  }
  .session-row:last-child { border-bottom: none; }
  .session-id { color: #79c0ff; }
  .ws-status { font-size: 12px; }
  .ws-on { color: #3fb950; }
  .ws-off { color: #484f58; }
  .empty-state { color: #484f58; font-size: 12px; font-style: italic; padding: 8px 0; }

  /* Chat */
  #chat-panel { grid-column: 1; grid-row: 2; }
  .chat-messages { flex: 1; overflow-y: auto; padding: 12px 14px; }
  .chat-msg { margin-bottom: 8px; font-size: 13px; line-height: 1.4; }
  .chat-msg .time { color: #484f58; margin-right: 6px; }
  .chat-msg .user { color: #d2a8ff; margin-right: 6px; font-weight: 600; }
  .chat-msg .text { color: #c9d1d9; }
  .chat-msg.sent { opacity: 0.7; }
  .chat-msg.sent .user { color: #79c0ff; }
  .send-status { font-size: 11px; color: #484f58; }
  .send-ok { color: #3fb950; }
  .send-fail { color: #f85149; }
  .chat-hint { font-size: 11px; color: #484f58; font-style: italic; padding: 4px 0 8px; border-bottom: 1px solid #21262d; margin-bottom: 8px; }
  .chat-input {
    display: flex; gap: 8px; padding: 10px 14px;
    background: #161b22; border-top: 1px solid #30363d; flex-shrink: 0;
  }
  .chat-input input {
    flex: 1; background: #0d1117; border: 1px solid #30363d; border-radius: 6px;
    padding: 8px 12px; color: #f0f6fc; font-family: inherit; font-size: 13px;
    outline: none;
  }
  .chat-input input:focus { border-color: #58a6ff; }
  .chat-input button {
    background: #238636; color: #fff; border: none; border-radius: 6px;
    padding: 8px 16px; font-family: inherit; font-size: 13px; cursor: pointer;
    font-weight: 600;
  }
  .chat-input button:hover { background: #2ea043; }
  .chat-input button:disabled { background: #21262d; color: #484f58; cursor: default; }

  /* Message History */
  .msg-row {
    display: flex; align-items: flex-start; gap: 8px;
    padding: 6px 0; border-bottom: 1px solid #21262d; font-size: 13px;
  }
  .msg-row:last-child { border-bottom: none; }
  .msg-dot { flex-shrink: 0; margin-top: 5px; width: 8px; height: 8px; border-radius: 50%; }
  .msg-dot.unread { background: #58a6ff; }
  .msg-dot.read { background: #30363d; }
  .msg-content { flex: 1; min-width: 0; }
  .msg-text { color: #c9d1d9; word-break: break-word; }
  .msg-meta { font-size: 11px; color: #484f58; margin-top: 2px; }
  .history-controls {
    display: flex; gap: 8px; padding: 10px 14px;
    background: #161b22; border-top: 1px solid #30363d; flex-shrink: 0;
  }
  .history-controls button {
    background: #21262d; color: #c9d1d9; border: 1px solid #30363d; border-radius: 6px;
    padding: 6px 12px; font-family: inherit; font-size: 12px; cursor: pointer;
  }
  .history-controls button:hover { background: #30363d; }

  @media (max-width: 768px) {
    .grid { grid-template-columns: 1fr; grid-template-rows: auto auto 1fr auto; height: auto; }
  }
</style>
</head>
<body>

<header>
  <h1>Slack Bot Dashboard</h1>
  <div class="conn-badge">
    <div class="conn-dot disconnected" id="conn-dot"></div>
    <span id="conn-label">connecting</span>
  </div>
</header>

<div class="grid">
  <!-- System Status -->
  <div class="panel">
    <div class="panel-header">System Status</div>
    <div class="panel-body" id="status-panel">
      <div class="empty-state">Loading...</div>
    </div>
  </div>

  <!-- Sessions -->
  <div class="panel">
    <div class="panel-header">Sessions</div>
    <div class="panel-body" id="sessions-panel">
      <div class="empty-state">Loading...</div>
    </div>
  </div>

  <!-- Chat -->
  <div class="panel" id="chat-panel">
    <div class="panel-header">Chat (real-time) <span id="ws-counter" style="float:right;font-size:10px;color:#484f58;font-weight:400;text-transform:none;letter-spacing:0"></span></div>
    <div class="chat-messages" id="chat-messages">
      <div class="chat-hint">Send posts to Slack. Incoming Slack messages appear here in real-time.</div>
    </div>
    <div class="chat-input">
      <input type="text" id="chat-input" placeholder="Type a message..." autocomplete="off">
      <button id="chat-send">Send</button>
    </div>
  </div>

  <!-- Message History -->
  <div class="panel">
    <div class="panel-header">Message History</div>
    <div class="panel-body" id="history-panel">
      <div class="empty-state">No messages</div>
    </div>
    <div class="history-controls">
      <button id="btn-mark-read">Mark All Read</button>
      <button id="btn-clear">Clear Queue</button>
      <button id="btn-refresh-history">Refresh</button>
    </div>
  </div>
</div>

<script>
(function() {
  const SESSION_ID = 'dash-' + Math.random().toString(16).slice(2, 6);
  const BASE = location.origin;
  let ws = null;
  let registered = false;
  let wsMessageCount = 0;

  // --- DOM refs ---
  const connDot = document.getElementById('conn-dot');
  const connLabel = document.getElementById('conn-label');
  const statusPanel = document.getElementById('status-panel');
  const sessionsPanel = document.getElementById('sessions-panel');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatSend = document.getElementById('chat-send');
  const historyPanel = document.getElementById('history-panel');

  // --- Helpers ---
  function timeStr(d) {
    return new Date(d).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function barColor(pct) {
    if (pct >= 90) return 'bar-red';
    if (pct >= 70) return 'bar-yellow';
    return 'bar-green';
  }

  function escHtml(s) {
    const d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  // --- Session registration ---
  async function registerSession() {
    try {
      const res = await fetch(BASE + '/sessions/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: SESSION_ID }),
      });
      if (res.ok) registered = true;
    } catch (e) {
      console.warn('Session register failed:', e);
    }
  }

  // --- WebSocket ---
  function connectWs() {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(proto + '//' + location.host + '/ws?session_id=' + SESSION_ID);

    ws.onopen = function() {
      connDot.className = 'conn-dot connected';
      connLabel.textContent = 'connected';
    };

    ws.onclose = function() {
      connDot.className = 'conn-dot disconnected';
      connLabel.textContent = 'disconnected';
      setTimeout(connectWs, 3000);
    };

    ws.onerror = function() {
      ws.close();
    };

    ws.onmessage = function(evt) {
      try {
        const data = JSON.parse(evt.data);
        wsMessageCount++;
        document.getElementById('ws-counter').textContent = 'ws:' + wsMessageCount;
        if (data.type === 'message' && data.message) {
          appendChatMessage(data.message);
          loadHistory();
        }
      } catch (e) {
        console.warn('WS parse error:', e);
      }
    };
  }

  // --- Chat ---
  function appendChatMessage(msg) {
    const div = document.createElement('div');
    div.className = 'chat-msg';
    div.innerHTML =
      '<span class="time">' + escHtml(timeStr(msg.receivedAt)) + '</span>' +
      '<span class="user">' + escHtml(msg.userId) + '</span>' +
      '<span class="text">' + escHtml(msg.text) + '</span>';
    chatMessages.appendChild(div);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  async function sendMessage() {
    const text = chatInput.value.trim();
    if (!text) return;
    chatInput.value = '';
    chatSend.disabled = true;

    // Show local echo immediately
    const div = document.createElement('div');
    div.className = 'chat-msg sent';
    const statusSpan = document.createElement('span');
    statusSpan.className = 'send-status';
    statusSpan.textContent = ' (sending...)';
    div.innerHTML =
      '<span class="time">' + escHtml(timeStr(new Date().toISOString())) + '</span>' +
      '<span class="user">you \\u2192 slack</span>' +
      '<span class="text">' + escHtml(text) + '</span>';
    div.querySelector('.text').appendChild(statusSpan);
    chatMessages.appendChild(div);
    chatMessages.scrollTop = chatMessages.scrollHeight;

    try {
      const res = await fetch(BASE + '/notify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, title: 'Dashboard', sessionId: SESSION_ID }),
      });
      if (res.ok) {
        statusSpan.textContent = ' \\u2713';
        statusSpan.className = 'send-status send-ok';
      } else {
        statusSpan.textContent = ' (failed)';
        statusSpan.className = 'send-status send-fail';
      }
    } catch (e) {
      console.warn('Send failed:', e);
      statusSpan.textContent = ' (failed)';
      statusSpan.className = 'send-status send-fail';
    }
    chatSend.disabled = false;
    chatInput.focus();
  }

  chatSend.addEventListener('click', sendMessage);
  chatInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') sendMessage();
  });

  // --- System Status ---
  async function loadStatus() {
    try {
      const res = await fetch(BASE + '/api/status');
      if (!res.ok) throw new Error('status ' + res.status);
      const s = await res.json();
      const cpuPct = Math.round(s.cpu.userPercent + s.cpu.systemPercent);
      const memPct = Math.round(s.memory.usedPercent);
      const dskPct = s.disk.usedPercent;
      const batPct = s.battery.percent;
      const batLabel = s.battery.charging ? batPct + '% (charging)' : batPct + '%';

      statusPanel.innerHTML =
        renderMetric('CPU', cpuPct + '%', cpuPct) +
        renderMetric('MEM', memPct + '% (' + s.memory.usedGB.toFixed(1) + '/' + s.memory.totalGB.toFixed(1) + ' GB)', memPct) +
        renderMetric('DSK', dskPct + '% (' + s.disk.usedGB + '/' + s.disk.sizeGB + ' GB)', dskPct) +
        renderMetric('BAT', batLabel, batPct) +
        '<div class="meta-info">' + escHtml(s.hostname) + ' &middot; up ' + escHtml(s.uptime) +
        ' &middot; load ' + s.cpu.loadAvg.map(function(v) { return v.toFixed(2); }).join(' ') + '</div>';
    } catch (e) {
      statusPanel.innerHTML = '<div class="empty-state">Failed to load status</div>';
    }
  }

  function renderMetric(label, value, pct) {
    return '<div class="metric">' +
      '<div class="metric-label"><span>' + label + '</span><span>' + escHtml(value) + '</span></div>' +
      '<div class="bar-bg"><div class="bar-fill ' + barColor(pct) + '" style="width:' + Math.min(pct, 100) + '%"></div></div>' +
      '</div>';
  }

  // --- Sessions ---
  async function loadSessions() {
    try {
      const res = await fetch(BASE + '/sessions');
      if (!res.ok) throw new Error('status ' + res.status);
      const data = await res.json();
      if (!data.sessions || data.sessions.length === 0) {
        sessionsPanel.innerHTML = '<div class="empty-state">No active sessions</div>';
        return;
      }
      sessionsPanel.innerHTML = data.sessions.map(function(s) {
        const wsClass = s.wsConnected ? 'ws-on' : 'ws-off';
        const wsIcon = s.wsConnected ? '\\u25cf' : '\\u25cb';
        return '<div class="session-row">' +
          '<span class="session-id">' + escHtml(s.id) + '</span>' +
          '<span class="ws-status ' + wsClass + '">WS: ' + wsIcon + '</span>' +
          '</div>';
      }).join('');
    } catch (e) {
      sessionsPanel.innerHTML = '<div class="empty-state">Failed to load sessions</div>';
    }
  }

  // --- Message History ---
  async function loadHistory() {
    try {
      const res = await fetch(BASE + '/messages?unread=false&limit=50');
      if (!res.ok) throw new Error('status ' + res.status);
      const data = await res.json();
      if (!data.messages || data.messages.length === 0) {
        historyPanel.innerHTML = '<div class="empty-state">No messages</div>';
        return;
      }
      historyPanel.innerHTML = data.messages.slice().reverse().map(function(m) {
        const dotClass = m.read ? 'read' : 'unread';
        return '<div class="msg-row">' +
          '<div class="msg-dot ' + dotClass + '"></div>' +
          '<div class="msg-content">' +
          '<div class="msg-text">' + escHtml(m.text) + '</div>' +
          '<div class="msg-meta">' + escHtml(m.userId) + ' &middot; ' + escHtml(timeStr(m.receivedAt)) +
          (m.targetSession ? ' &middot; @' + escHtml(m.targetSession) : '') + '</div>' +
          '</div></div>';
      }).join('');
    } catch (e) {
      historyPanel.innerHTML = '<div class="empty-state">Failed to load messages</div>';
    }
  }

  // --- History controls ---
  document.getElementById('btn-mark-read').addEventListener('click', async function() {
    try {
      await fetch(BASE + '/messages/mark-read', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      loadHistory();
    } catch (e) { console.warn('Mark read failed:', e); }
  });

  document.getElementById('btn-clear').addEventListener('click', async function() {
    if (!confirm('Clear all queued messages?')) return;
    try {
      await fetch(BASE + '/messages', { method: 'DELETE' });
      loadHistory();
    } catch (e) { console.warn('Clear failed:', e); }
  });

  document.getElementById('btn-refresh-history').addEventListener('click', loadHistory);

  // --- Cleanup ---
  window.addEventListener('beforeunload', function() {
    if (registered) {
      navigator.sendBeacon(BASE + '/sessions/' + SESSION_ID + '?_method=DELETE');
      fetch(BASE + '/sessions/' + SESSION_ID, { method: 'DELETE', keepalive: true }).catch(function() {});
    }
  });

  // --- Load recent messages into chat ---
  async function loadRecentChat() {
    try {
      const res = await fetch(BASE + '/messages?unread=false&limit=50');
      if (!res.ok) return;
      const data = await res.json();
      if (data.messages && data.messages.length > 0) {
        data.messages.forEach(function(m) { appendChatMessage(m); });
      }
    } catch (e) { /* ignore */ }
  }

  // --- Init ---
  async function init() {
    await registerSession();
    connectWs();
    loadStatus();
    loadSessions();
    loadHistory();
    loadRecentChat();
    setInterval(loadStatus, 10000);
    setInterval(loadSessions, 10000);
  }

  init();
})();
</script>
</body>
</html>`;
}

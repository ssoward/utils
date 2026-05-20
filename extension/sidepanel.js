// ChromeCC side panel chat logic

const messagesEl = document.getElementById('messages');
const inputEl = document.getElementById('input');
const sendBtn = document.getElementById('send');
const newChatBtn = document.getElementById('new-chat');
const pageContextEl = document.getElementById('page-context');

let currentTabId = null;
let isStreaming = false;
let currentAssistantEl = null;

async function getActiveTabId() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab?.id || null;
}

async function init() {
  currentTabId = await getActiveTabId();
  if (currentTabId) {
    updatePageContext();
    loadHistory();
  }
}

async function updatePageContext() {
  try {
    const response = await chrome.tabs.sendMessage(currentTabId, { type: 'get-page-content' });
    if (response && response.url) {
      pageContextEl.textContent = '\u{1F4C4} ' + response.url;
      pageContextEl.classList.add('visible');
    }
  } catch {
    pageContextEl.classList.remove('visible');
  }
}

async function loadHistory() {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage({ type: 'get-history', tabId: currentTabId }, (response) => {
      if (response && response.history) {
        for (const msg of response.history) {
          appendMessage(msg.role === 'user' ? 'user' : 'assistant', msg.content);
        }
      }
      resolve();
    });
  });
}

async function sendMessage() {
  const text = inputEl.value.trim();
  if (!text || isStreaming) return;

  currentTabId = await getActiveTabId();
  if (!currentTabId) return;

  appendMessage('user', text);
  inputEl.value = '';
  inputEl.style.height = 'auto';
  setStreaming(true);

  showTyping();

  chrome.runtime.sendMessage({
    type: 'user-message',
    tabId: currentTabId,
    text: text
  });
}

function appendMessage(role, content) {
  const div = document.createElement('div');
  div.className = `message ${role}`;
  if (role === 'assistant') {
    div.innerHTML = renderMarkdown(content);
  } else {
    div.textContent = content;
  }
  messagesEl.appendChild(div);
  scrollToBottom();
  return div;
}

function showTyping() {
  removeTyping();
  const div = document.createElement('div');
  div.className = 'typing';
  div.id = 'typing-indicator';
  div.textContent = '\u25CF \u25CF \u25CF';
  messagesEl.appendChild(div);
  scrollToBottom();
}

function removeTyping() {
  const el = document.getElementById('typing-indicator');
  if (el) el.remove();
}

function startAssistantMessage() {
  removeTyping();
  currentAssistantEl = document.createElement('div');
  currentAssistantEl.className = 'message assistant';
  messagesEl.appendChild(currentAssistantEl);
  return currentAssistantEl;
}

function appendChunk(text) {
  if (!currentAssistantEl) {
    startAssistantMessage();
  }
  if (!currentAssistantEl._rawText) {
    currentAssistantEl._rawText = '';
  }
  currentAssistantEl._rawText += text;
  currentAssistantEl.innerHTML = renderMarkdown(currentAssistantEl._rawText);
  scrollToBottom();
}

function setStreaming(value) {
  isStreaming = value;
  sendBtn.disabled = value;
  inputEl.disabled = value;
  if (!value) {
    inputEl.focus();
  }
}

function renderMarkdown(text) {
  let html = text;

  html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, (_, lang, code) => {
    return `<pre><code>${code.trim()}</code></pre>`;
  });

  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  html = html.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>');

  html = html.replace(/^[\u2022\-\*] (.+)$/gm, '<li>$1</li>');
  html = html.replace(/(<li>.*<\/li>\n?)+/g, '<ul>$&</ul>');

  html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');

  html = html.replace(/\n\n/g, '<br><br>');
  html = html.replace(/\n/g, '<br>');

  return html;
}

function scrollToBottom() {
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

chrome.runtime.onMessage.addListener((message) => {
  if (message.tabId !== currentTabId) return;

  if (message.type === 'chunk') {
    appendChunk(message.text);
  } else if (message.type === 'done') {
    currentAssistantEl = null;
    setStreaming(false);
  } else if (message.type === 'error') {
    removeTyping();
    currentAssistantEl = null;
    setStreaming(false);
    const div = document.createElement('div');
    div.className = 'message error';
    div.textContent = message.error;
    messagesEl.appendChild(div);
    scrollToBottom();
  }
});

sendBtn.addEventListener('click', sendMessage);

inputEl.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
});

inputEl.addEventListener('input', () => {
  inputEl.style.height = 'auto';
  inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + 'px';
});

newChatBtn.addEventListener('click', async () => {
  currentTabId = await getActiveTabId();
  chrome.runtime.sendMessage({ type: 'clear-history', tabId: currentTabId });
  messagesEl.innerHTML = '';
  currentAssistantEl = null;
  setStreaming(false);
});

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  currentTabId = activeInfo.tabId;
  messagesEl.innerHTML = '';
  currentAssistantEl = null;
  updatePageContext();
  loadHistory();
});

init();

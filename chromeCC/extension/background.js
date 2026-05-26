// ChromeCC background service worker
// Routes messages between side panel, content script, and native host

const NATIVE_HOST = 'com.anthropic.chromecc';
const MAX_HISTORY = 20;

const tabHistory = new Map();

chrome.action.onClicked.addListener((tab) => {
  chrome.sidePanel.open({ tabId: tab.id });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  tabHistory.delete(tabId);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'user-message') {
    handleUserMessage(message.tabId, message.text);
  } else if (message.type === 'clear-history') {
    tabHistory.delete(message.tabId);
  } else if (message.type === 'get-history') {
    sendResponse({ history: tabHistory.get(message.tabId) || [] });
    return true;
  }
});

async function handleUserMessage(tabId, userText) {
  let pageContent = null;
  try {
    const [response] = await chrome.tabs.sendMessage(tabId, { type: 'get-page-content' })
      .then(r => [r])
      .catch(() => [null]);
    pageContent = response;
  } catch (e) {
    // Content script may not be injected (chrome:// pages, etc.)
  }

  if (!tabHistory.has(tabId)) {
    tabHistory.set(tabId, []);
  }
  const history = tabHistory.get(tabId);
  history.push({ role: 'user', content: userText });

  let prompt = '';

  if (pageContent) {
    prompt += `[Page context: "${pageContent.title}" at ${pageContent.url}`;
    if (pageContent.pageText) {
      prompt += `\nPage content (truncated): ${pageContent.pageText}`;
    }
    if (pageContent.selectedText) {
      prompt += `\nUser-selected text: ${pageContent.selectedText}`;
    }
    prompt += ']\n\n';
  }

  const cappedHistory = history.slice(-(MAX_HISTORY * 2));
  for (const msg of cappedHistory) {
    if (msg.role === 'user') {
      prompt += `Human: ${msg.content}\n\n`;
    } else {
      prompt += `Assistant: ${msg.content}\n\n`;
    }
  }

  let port;
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST);
  } catch (e) {
    broadcastToSidePanel(tabId, {
      type: 'error',
      error: 'Native host not found. Run install.sh to set up ChromeCC.'
    });
    return;
  }

  let fullResponse = '';

  port.onMessage.addListener((msg) => {
    if (msg.type === 'chunk') {
      fullResponse += msg.text;
      broadcastToSidePanel(tabId, { type: 'chunk', text: msg.text });
    } else if (msg.type === 'done') {
      history.push({ role: 'assistant', content: fullResponse });
      while (history.length > MAX_HISTORY * 2) {
        history.shift();
      }
      broadcastToSidePanel(tabId, { type: 'done' });
    } else if (msg.type === 'error') {
      broadcastToSidePanel(tabId, { type: 'error', error: msg.error });
    }
  });

  port.onDisconnect.addListener(() => {
    if (chrome.runtime.lastError) {
      const errMsg = chrome.runtime.lastError.message || '';
      let userError = 'Connection lost. Reopen the sidebar to reconnect.';
      if (errMsg.includes('not found') || errMsg.includes('Specified native messaging host not found')) {
        userError = 'Native host not found. Run install.sh to set up ChromeCC.';
      }
      broadcastToSidePanel(tabId, { type: 'error', error: userError });
    }
  });

  port.postMessage({ type: 'prompt', prompt: prompt });
}

function broadcastToSidePanel(tabId, message) {
  chrome.runtime.sendMessage({ ...message, tabId: tabId }).catch(() => {
    // Side panel may not be open
  });
}

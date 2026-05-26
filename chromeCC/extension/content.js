// ChromeCC content script — extracts page content on request

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === 'get-page-content') {
    const pageText = (document.body.innerText || '').substring(0, 4000);
    const selectedText = window.getSelection().toString().substring(0, 2000);

    sendResponse({
      title: document.title,
      url: window.location.href,
      pageText: pageText,
      selectedText: selectedText
    });
  }
  return true;
});

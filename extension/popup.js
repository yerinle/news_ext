const api = typeof browser !== 'undefined' ? browser : chrome;

const el = (id) => document.getElementById(id);
let currentTab = null;
let currentHost = null;

function send(message) {
  return new Promise((resolve) => {
    const p = api.runtime.sendMessage(message, resolve);
    if (p && typeof p.then === 'function') p.then(resolve);
  });
}

async function init() {
  const tabs = await new Promise((r) => {
    const p = api.tabs.query({ active: true, currentWindow: true }, r);
    if (p && typeof p.then === 'function') p.then(r);
  });
  currentTab = tabs && tabs[0];
  if (!currentTab || !currentTab.url || !/^https?:/.test(currentTab.url)) {
    el('open').disabled = true;
    el('status').textContent = 'No web page in this tab.';
    return;
  }
  currentHost = new URL(currentTab.url).hostname.replace(/^www\./, '');
  el('host').textContent = currentHost;

  const status = await send({ action: 'getStatus', host: currentHost });
  el('always').checked = !!(status && status.allowed);
  el('enabled').checked = !!(status && status.enabled);
}

el('open').addEventListener('click', async () => {
  el('status').textContent = 'Handing off to News…';
  const result = await send({ action: 'openInNews', url: currentTab.url });
  el('status').textContent = (result && result.ok === false)
    ? `Failed: ${result.error || 'native helper unavailable'}`
    : 'Sent to News.';
});

el('always').addEventListener('change', async (e) => {
  await send({ action: 'setDomain', host: currentHost, value: e.target.checked ? true : false });
});

el('enabled').addEventListener('change', async (e) => {
  await send({ action: 'setEnabled', value: e.target.checked });
});

el('options').addEventListener('click', (e) => {
  e.preventDefault();
  api.runtime.openOptionsPage();
});

init();

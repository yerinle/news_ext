/*
 * NewsOpen background worker.
 *
 * Watches top-level navigations, and when one looks like an article from an
 * Apple News+ publisher, asks the native helper to hand the URL to the system
 * "Open in News" share service.
 *
 * Two things shape the design, both established by testing News.app directly:
 *
 *  1. The share service always reports success, even for a URL that has no
 *     News+ article (it silently drops to the "Today" screen). There is no
 *     failure signal, so we never close or navigate the tab away — a bad guess
 *     costs you a switch back to the browser, never the page itself.
 *
 *  2. applenews:// and applenewss:// only launch the app, they do not resolve
 *     articles. The native share service is the only thing that works.
 */

const api = typeof browser !== 'undefined' ? browser : chrome;

// Set by target.js, written when the extension is staged for Safari or Chrome.
const NATIVE_APP = self.NATIVE_APP_ID || 'com.yinka.newsopen';

const DEDUPE_MS = 5000;          // ignore repeat navigations to the same URL
const RETURN_WINDOW_MS = 90000;  // coming back this soon means "I want the web"
const SUPPRESS_TTL_MS = 900000;  // ...so leave that URL alone for 15 minutes

const DEFAULTS = {
  enabled: true,
  domains: {},      // host -> true (always) / false (never); overrides the seed list
  lastRedirect: {}, // url -> timestamp
  suppressed: {}    // url -> timestamp until which we leave it alone
};

async function getState() {
  const stored = await api.storage.local.get(DEFAULTS);
  return { ...DEFAULTS, ...stored };
}

function normalizeHost(hostname) {
  return hostname.replace(/^www\./, '').toLowerCase();
}

/* A host matches if it or any parent domain is allowlisted. */
function hostDecision(host, domains) {
  const parts = host.split('.');
  for (let i = 0; i < parts.length - 1; i++) {
    const candidate = parts.slice(i).join('.');
    if (Object.prototype.hasOwnProperty.call(domains, candidate)) {
      return domains[candidate];      // explicit user choice wins
    }
    if (self.DEFAULT_PUBLISHERS.includes(candidate)) {
      return true;
    }
  }
  return false;
}

/*
 * Cheap structural test for "this is an article, not a section index".
 * Section fronts, search, and account pages have no News+ article behind them,
 * and redirecting on those is the most irritating false positive.
 */
const NON_ARTICLE = /^\/?(search|account|login|signin|sign-in|register|subscribe|subscription|newsletters?|tag|tags|topic|topics|author|authors|category|categories|page|archive|about|contact|privacy|terms)(\/|$)/i;

function looksLikeArticle(urlString) {
  let url;
  try {
    url = new URL(urlString);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return false;

  const path = url.pathname.replace(/\/+$/, '');
  if (!path || path === '') return false;          // homepage
  if (NON_ARTICLE.test(path)) return false;

  const segments = path.split('/').filter(Boolean);
  if (segments.length === 0) return false;

  const last = segments[segments.length - 1];

  // A dated path (/2026/09/18/...) is almost always an article.
  if (/\/\d{4}\/\d{1,2}\//.test(path)) return true;

  // Otherwise expect a slug: hyphenated and reasonably long.
  if (last.includes('-') && last.length >= 12) return true;

  // Some publishers use /story/<id> or /article/<id>.
  if (segments.length >= 2 && /^(story|article|articles|post)$/i.test(segments[segments.length - 2])) return true;

  return false;
}

function prune(map, ttl, now) {
  const out = {};
  for (const [key, ts] of Object.entries(map || {})) {
    if (now - ts < ttl) out[key] = ts;
  }
  return out;
}

function sendNative(url) {
  const message = { action: 'open', url };
  return new Promise((resolve) => {
    try {
      const maybePromise = api.runtime.sendNativeMessage(NATIVE_APP, message, (response) => {
        const err = api.runtime.lastError;
        resolve(err ? { ok: false, error: err.message } : (response || { ok: true }));
      });
      // Safari returns a promise instead of using the callback.
      if (maybePromise && typeof maybePromise.then === 'function') {
        maybePromise.then((r) => resolve(r || { ok: true }), (e) => resolve({ ok: false, error: String(e) }));
      }
    } catch (e) {
      resolve({ ok: false, error: String(e) });
    }
  });
}

/* Shared by the automatic path and the toolbar button. */
async function openInNews(url, { manual = false } = {}) {
  const now = Date.now();
  const state = await getState();

  if (!manual) {
    const last = state.lastRedirect[url];
    if (last && now - last < DEDUPE_MS) return { ok: false, reason: 'duplicate' };
  }

  const result = await sendNative(url);

  state.lastRedirect = prune(state.lastRedirect, RETURN_WINDOW_MS, now);
  state.lastRedirect[url] = now;
  await api.storage.local.set({ lastRedirect: state.lastRedirect });

  return result;
}

api.webNavigation.onBeforeNavigate.addListener(async (details) => {
  if (details.frameId !== 0) return;

  const now = Date.now();
  const state = await getState();
  if (!state.enabled) return;

  const url = details.url;
  let host;
  try {
    host = normalizeHost(new URL(url).hostname);
  } catch {
    return;
  }

  if (hostDecision(host, state.domains) !== true) return;
  if (!looksLikeArticle(url)) return;

  // Escape hatch: if this URL is parked, the user deliberately wants the web version.
  const suppressedUntil = state.suppressed[url];
  if (suppressedUntil && now < suppressedUntil) return;

  // Coming back to a URL we just redirected means the News hand-off was not
  // what the user wanted. Park it and stay out of the way.
  const last = state.lastRedirect[url];
  if (last && now - last > DEDUPE_MS && now - last < RETURN_WINDOW_MS) {
    state.suppressed = prune(state.suppressed, SUPPRESS_TTL_MS, now);
    state.suppressed[url] = now + SUPPRESS_TTL_MS;
    delete state.lastRedirect[url];
    await api.storage.local.set({ suppressed: state.suppressed, lastRedirect: state.lastRedirect });
    return;
  }

  await openInNews(url);
});

/* Toolbar button and options page talk to us through here. */
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    if (message.action === 'openInNews') {
      sendResponse(await openInNews(message.url, { manual: true }));
      return;
    }
    if (message.action === 'getStatus') {
      const state = await getState();
      const host = message.host ? normalizeHost(message.host) : null;
      sendResponse({
        enabled: state.enabled,
        host,
        allowed: host ? hostDecision(host, state.domains) === true : false,
        explicit: host ? Object.prototype.hasOwnProperty.call(state.domains, host) : false
      });
      return;
    }
    if (message.action === 'setDomain') {
      const state = await getState();
      const host = normalizeHost(message.host);
      if (message.value === null) {
        delete state.domains[host];
      } else {
        state.domains[host] = message.value;
      }
      await api.storage.local.set({ domains: state.domains });
      sendResponse({ ok: true });
      return;
    }
    if (message.action === 'setEnabled') {
      await api.storage.local.set({ enabled: !!message.value });
      sendResponse({ ok: true });
      return;
    }
    sendResponse({ ok: false, error: 'unknown action' });
  })();
  return true; // keep the message channel open for the async response
});

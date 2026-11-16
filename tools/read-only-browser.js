'use strict';

// Runs before page scripts. Preserve native GET/CORS behavior; do not use
// Playwright request routing, which can bypass Chromium's CORS preflight.
/** @param {any} options */
function installReadOnlyBrowser(options = {}) {
  const browser = /** @type {any} */ (globalThis);
  const telemetry = options.telemetry || [];
  const target = value => {
    try { return new URL(typeof value === 'string' || value instanceof URL ? String(value) : value?.url, browser.location.href); }
    catch { return null; }
  };
  const isTelemetry = value => {
    const url = target(value);
    return url && telemetry.some(entry => url.pathname === entry.path &&
      (entry.origin ? url.origin === entry.origin : url.hostname.endsWith(entry.hostnameSuffix)));
  };
  const report = (api, value, unavailable = false) => {
    const url = target(value);
    const record = { api, path: url?.pathname || '', unavailable };
    const emit = browser[options.reportName];
    if (typeof emit === 'function') Promise.resolve(emit(record)).catch(() => {});
  };
  const refused = (api, url, unavailable = false) => {
    report(api, url, unavailable);
    return new TypeError('Read-only verification refused ' + api);
  };
  if (typeof browser.fetch === 'function') {
    const native = browser.fetch.bind(browser);
    browser.fetch = (input, init) => {
      if (isTelemetry(input)) return Promise.resolve(new Response(null, { status: 204 }));
      const method = String(init?.method || input?.method || 'GET').toUpperCase();
      return method === 'GET' ? native(input, init) : Promise.reject(refused(method, input));
    };
  }
  if (browser.XMLHttpRequest) {
    const methods = new WeakMap(), prototype = browser.XMLHttpRequest.prototype;
    const open = prototype.open, send = prototype.send;
    prototype.open = function(method, url, ...rest) {
      methods.set(this, { method: String(method).toUpperCase(), url });
      return open.call(this, method, url, ...rest);
    };
    prototype.send = function(...args) {
      const request = methods.get(this);
      if (request && isTelemetry(request.url)) return;
      if (request && request.method !== 'GET') throw refused(request.method, request.url);
      return send.apply(this, args);
    };
  }
  if (browser.navigator?.sendBeacon) {
    browser.navigator.sendBeacon = url => {
      if (isTelemetry(url)) return true;
      report('sendBeacon', url);
      return false;
    };
  }
  if (browser.HTMLFormElement) {
    const prototype = browser.HTMLFormElement.prototype;
    for (const name of ['submit', 'requestSubmit']) {
      if (prototype[name]) prototype[name] = function() { throw refused('form submission', this.action); };
    }
    // Refuse even an initially-GET form: a later application handler can turn
    // it into POST after this capture handler, before the browser's default.
    browser.document.addEventListener('submit', event => {
      event.preventDefault();
      report('form submission', event.target.action);
    }, true);
  }
  // These bounded walks navigate explicit URLs, never native links. Cancel
  // activation even without ping: a later click handler can add that POST.
  const isLink = value => value instanceof browser.HTMLAnchorElement || value instanceof browser.HTMLAreaElement;
  browser.document.addEventListener('click', event => {
    const link = event.target.closest?.('a, area');
    if (link) { event.preventDefault(); report('link activation', link.href); }
  }, true);
  const click = browser.HTMLElement.prototype.click;
  browser.HTMLElement.prototype.click = function() {
    if (isLink(this)) { report('link activation', this.href); return; }
    return click.call(this);
  };
  const dispatch = browser.EventTarget.prototype.dispatchEvent;
  browser.EventTarget.prototype.dispatchEvent = function(event) {
    if (isLink(this) && event.type === 'click') { report('link activation', this.href); return false; }
    return dispatch.call(this, event);
  };
  for (const name of ['Worker', 'SharedWorker', 'WebSocket', 'WebTransport', 'RTCPeerConnection']) {
    if (typeof browser[name] === 'function') browser[name] = function(url) { throw refused(name, url, true); };
  }
}

// User-Agent is a native browser header, unlike a global custom header that
// forces CORS preflight on otherwise-simple third-party reads.
/** @param {any} browser */
async function probeUserAgent(browser) {
  const page = await browser.newPage();
  try { return await page.evaluate(() => navigator.userAgent) + ' BiV-Live-Check/1'; }
  finally { await page.close(); }
}

// Intercept only browser-native request types. Routing Fetch/XHR/Script or
// Preflight would change CORS; the negative and positive CORS fixtures own it.
/** @param {any} page @param {(record: any) => void} onViolation */
async function installNativeWriteGuard(page, onViolation) {
  const session = await page.context().newCDPSession(page);
  session.on('Page.windowOpen', () => onViolation({ api: 'new browser target', path: '', unavailable: true }));
  await session.send('Page.enable');
  session.on('Fetch.requestPaused', event => {
    const blocked = event.request.method !== 'GET';
    const record = { api: event.request.method, path: new URL(event.request.url).pathname, unavailable: false };
    if (blocked) onViolation(record);
    const command = blocked ? session.send('Fetch.failRequest', { requestId: event.requestId, errorReason: 'BlockedByClient' })
      : session.send('Fetch.continueRequest', { requestId: event.requestId });
    command.catch(() => onViolation({ api: 'native request guard', path: '', unavailable: true }));
  });
  await session.send('Fetch.enable', { patterns: ['Document', 'Ping', 'CSPViolationReport'].map(resourceType => ({ resourceType, requestStage: 'Request' })) });
}

module.exports = { installReadOnlyBrowser, probeUserAgent, installNativeWriteGuard };

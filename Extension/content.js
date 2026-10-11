// MC Download Manager — content script
// 1) In Safari (no downloads API) intercepts clicks on file links.
// 2) Reports <video>/<audio>/<source> URLs on the page to the background script.
//    MSE players (YouTube, X, etc.) expose blob: URLs, so playing <video> elements are
//    also reported as page videos. Those entries are downloaded through yt-dlp using
//    the page URL rather than the unusable, tab-local blob URL.
(() => {
  'use strict';
  const api = typeof browser !== 'undefined' ? browser : chrome;
  const DL_EXT = /\.(zip|rar|7z|tar|gz|tgz|bz2|xz|dmg|pkg|iso|exe|msi|apk|deb|rpm|pdf|epub|mobi|doc|docx|xls|xlsx|ppt|pptx|mp4|mkv|avi|mov|webm|mp3|flac|wav|m4a|aac|ogg|jar|bin|img|csv|psd|ai|ttf|otf|woff2?)(\?|#|$)/i;

  let state = { online: false, clickIntercept: false, settings: { intercept: true } };

  // Firefox's browser.runtime.sendMessage only returns a promise (a callback argument is rejected).
  const IS_FIREFOX = typeof browser !== 'undefined' && String(browser.runtime.getURL('')).startsWith('moz-extension:');

  function sendMessage(message) {
    try {
      const result = api.runtime.sendMessage(message);
      // Firefox returns a promise. Consume rejections when the extension is reloaded while
      // a content script from the previous version is still attached to a tab.
      if (result && typeof result.catch === 'function') result.catch(() => {});
    } catch {}
  }

  function refresh() {
    const apply = (r) => { if (r) state = r; };
    try {
      if (IS_FIREFOX) {
        browser.runtime.sendMessage({ type: 'status' }).then(apply, () => {});
      } else {
        api.runtime.sendMessage({ type: 'status' }, (r) => { if (!api.runtime.lastError) apply(r); });
      }
    } catch {}
  }
  refresh();
  setInterval(refresh, 30000);

  document.addEventListener('click', (e) => {
    if (!state.clickIntercept || !state.online || !state.settings?.intercept) return;
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
    const a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    const href = a.href;
    if (!/^https?:/i.test(href)) return;
    const list = state.captureExtensions || [];
    const m = href.split(/[?#]/)[0].match(/\.([a-z0-9]{1,8})$/i);
    const ext = m ? m[1].toLowerCase() : '';
    if (list.length ? !(ext && list.includes(ext)) : !(a.hasAttribute('download') || DL_EXT.test(href))) return;
    e.preventDefault();
    e.stopPropagation();
    sendMessage({ type: 'download', url: href, filename: a.getAttribute('download') || '', referer: location.href, kind: 'file' });
  }, true);

  const reported = new Map();
  function addOnce(items, key, signature, item) {
    if (reported.get(key) === signature) return;
    reported.set(key, signature);
    items.push(item);
  }

  function scanMedia() {
    const items = [];
    document.querySelectorAll('video, audio, source').forEach((el) => {
      const src = el.currentSrc || el.src || el.getAttribute('src');
      const type = el.getAttribute('type') || '';
      const name = document.title ? document.title.trim().slice(0, 150) : '';

      if (src && /^https?:/i.test(src)) {
        addOnce(items, 'source:' + src, src, { url: src, type, name });
      }

      if (el.tagName === 'VIDEO' && !el.paused && !el.ended && el.readyState > 0 && /^https?:/i.test(location.href)) {
        const signature = [location.href, name, src || ''].join('\n');
        addOnce(items, 'page-video:' + location.href, signature, {
          url: location.href,
          pageUrl: location.href,
          sourceUrl: src || '',
          type,
          name,
          kind: 'page-video',
        });
      }
    });
    if (items.length) sendMessage({ type: 'pageMedia', items });
  }
  scanMedia();
  document.addEventListener('play', scanMedia, true);
  document.addEventListener('loadedmetadata', scanMedia, true);
  // YouTube and similar single-page apps replace players without reloading the content
  // script. Keep the inexpensive scan alive so later videos are captured as well.
  setInterval(scanMedia, 3000);
})();

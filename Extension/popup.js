'use strict';
const api = typeof browser !== 'undefined' ? browser : chrome;
const $ = (id) => document.getElementById(id);
const t = (k, subs) => { try { return api.i18n.getMessage(k, subs) || k; } catch { return k; } };

document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
document.documentElement.lang = (() => { try { return api.i18n.getUILanguage(); } catch { return 'en'; } })();

function send(msg) {
  return new Promise((resolve) => {
    try {
      api.runtime.sendMessage(msg, (r) => resolve(api.runtime.lastError ? null : r));
    } catch { resolve(null); }
  });
}
function fmtSize(n) {
  if (!n) return '';
  const u = ['B', 'KB', 'MB', 'GB'];
  let i = 0; while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return n.toFixed(i ? 1 : 0) + ' ' + u[i];
}

let tab = null;

async function currentTab() {
  const tabs = await api.tabs.query({ active: true, currentWindow: true });
  return tabs && tabs[0];
}

async function refresh() {
  const st = await send({ type: 'status' });
  const online = !!(st && st.online);
  $('dot').classList.toggle('on', online);
  $('statusText').textContent = online
    ? t('popupConnected', [String(st.app.version)]) + (st.app.active ? ` · ${t('popupActive', [String(st.app.active)])}` : '')
    : t('popupOffline');
  $('offline').classList.toggle('hidden', online);
  $('launch').classList.toggle('hidden', !(st && st.isSafari));
  if (st && st.settings) {
    $('intercept').checked = !!st.settings.intercept;
    $('sniff').checked = !!st.settings.sniff;
    $('port').value = st.settings.port;
    $('minSize').value = st.settings.minSizeMB || 0;
  }
}

async function loadMedia() {
  tab = await currentTab();
  const list = (tab && (await send({ type: 'getMedia', tabId: tab.id }))) || [];
  const ul = $('media');
  ul.innerHTML = '';
  $('count').textContent = list.length ? `(${list.length})` : '';
  $('noMedia').classList.toggle('hidden', list.length > 0);
  for (const m of list) {
    const li = document.createElement('li');
    const info = document.createElement('div'); info.className = 'info';
    const name = document.createElement('div'); name.className = 'name'; name.textContent = m.name || m.url; name.title = m.url;
    const meta = document.createElement('div'); meta.className = 'meta';
    const kind = m.kind === 'hls' ? t('kindHls') : m.kind === 'dash' ? t('kindDash') : (m.type || t('kindMedia'));
    meta.textContent = [kind, fmtSize(m.size)].filter(Boolean).join(' · ');
    info.append(name, meta);
    const btn = document.createElement('button'); btn.className = 'small'; btn.textContent = t('popupDownload');
    btn.onclick = async () => {
      btn.disabled = true; btn.textContent = '…';
      const k = m.kind === 'hls' || m.kind === 'dash' ? 'video' : 'file';
      const r = await send({ type: 'download', url: m.url, filename: k === 'file' ? m.name : '', referer: tab.url, kind: k });
      btn.textContent = r && r.ok ? t('popupSent') : t('popupError');
    };
    li.append(info, btn);
    ul.appendChild(li);
  }
}

$('pageVideo').onclick = async () => {
  tab = tab || (await currentTab());
  if (!tab?.url) return;
  $('pageVideo').textContent = t('popupSending');
  const r = await send({ type: 'download', url: tab.url, referer: tab.url, kind: 'video' });
  $('pageVideo').textContent = r && r.ok ? t('popupStarted') : t('popupFailed');
  setTimeout(() => ($('pageVideo').textContent = t('popupPageVideo')), 2500);
};
$('pageLink').onclick = async () => {
  tab = tab || (await currentTab());
  if (!tab?.url) return;
  await send({ type: 'download', url: tab.url, referer: tab.url, kind: 'file' });
  window.close();
};
$('launch').onclick = async () => {
  await send({ type: 'launchApp' });
  setTimeout(refresh, 1500);
};
$('intercept').onchange = (e) => send({ type: 'setSettings', settings: { intercept: e.target.checked } });
$('sniff').onchange = (e) => send({ type: 'setSettings', settings: { sniff: e.target.checked } });
$('port').onchange = (e) => send({ type: 'setSettings', settings: { port: parseInt(e.target.value, 10) || 48213 } }).then(refresh);
$('minSize').onchange = (e) => send({ type: 'setSettings', settings: { minSizeMB: parseInt(e.target.value, 10) || 0 } });

refresh();
loadMedia();

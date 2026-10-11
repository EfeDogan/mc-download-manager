import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const contentScript = await readFile(new URL('../Extension/content.js', import.meta.url), 'utf8');

function runContentScript(video, engine = 'firefox') {
  const messages = [];
  const listeners = new Map();
  const runtime = {
    lastError: null,
    getURL: () => engine === 'firefox'
      ? 'moz-extension://mc-download-manager/'
      : 'chrome-extension://mc-download-manager/',
    sendMessage(message, callback) {
      messages.push(message);
      const response = { online: true, settings: { intercept: true } };
      if (callback) {
        callback(response);
        return undefined;
      }
      return Promise.resolve(response);
    },
  };
  const document = {
    title: 'Test video - YouTube',
    querySelectorAll: () => [video],
    addEventListener: (type, listener) => listeners.set(type, listener),
  };
  const context = {
    document,
    location: { href: 'https://www.youtube.com/watch?v=test123' },
    setInterval: () => 1,
    clearInterval: () => {},
  };
  context[engine === 'firefox' ? 'browser' : 'chrome'] = { runtime };
  vm.runInNewContext(contentScript, context, { filename: 'Extension/content.js' });
  return { messages, listeners };
}

function fakeVideo(overrides = {}) {
  return {
    tagName: 'VIDEO',
    currentSrc: 'blob:https://www.youtube.com/player-stream',
    src: '',
    paused: false,
    ended: false,
    readyState: 4,
    getAttribute: () => '',
    ...overrides,
  };
}

for (const engine of ['firefox', 'chromium']) {
  test(`a playing blob-backed video is reported in ${engine} using its downloadable page URL`, () => {
    const { messages } = runContentScript(fakeVideo(), engine);
    const report = messages.find((message) => message.type === 'pageMedia');
    assert.ok(report, 'content script must report the playing video');
    assert.deepEqual(JSON.parse(JSON.stringify(report.items[0])), {
      url: 'https://www.youtube.com/watch?v=test123',
      pageUrl: 'https://www.youtube.com/watch?v=test123',
      sourceUrl: 'blob:https://www.youtube.com/player-stream',
      type: '',
      name: 'Test video - YouTube',
      kind: 'page-video',
    });
  });
}

test('a paused Chromium video is reported when playback starts', () => {
  const video = fakeVideo({ paused: true });
  const { messages, listeners } = runContentScript(video, 'chromium');
  assert.equal(messages.some((message) => message.type === 'pageMedia'), false);

  video.paused = false;
  listeners.get('play')();
  assert.equal(messages.some((message) => message.type === 'pageMedia'), true);
});

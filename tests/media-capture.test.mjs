import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';

const contentScript = await readFile(new URL('../Extension/content.js', import.meta.url), 'utf8');

function runContentScript(video) {
  const messages = [];
  const listeners = new Map();
  const browser = {
    runtime: {
      getURL: () => 'moz-extension://mc-download-manager/',
      sendMessage(message) {
        messages.push(message);
        return Promise.resolve({ online: true, settings: { intercept: true } });
      },
    },
  };
  const document = {
    title: 'Test video - YouTube',
    querySelectorAll: () => [video],
    addEventListener: (type, listener) => listeners.set(type, listener),
  };
  const context = {
    browser,
    document,
    location: { href: 'https://www.youtube.com/watch?v=test123' },
    setInterval: () => 1,
    clearInterval: () => {},
  };
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

test('a playing blob-backed video is reported using its downloadable page URL', () => {
  const { messages } = runContentScript(fakeVideo());
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

test('a paused video is reported when playback starts', () => {
  const video = fakeVideo({ paused: true });
  const { messages, listeners } = runContentScript(video);
  assert.equal(messages.some((message) => message.type === 'pageMedia'), false);

  video.paused = false;
  listeners.get('play')();
  assert.equal(messages.some((message) => message.type === 'pageMedia'), true);
});

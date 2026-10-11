import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const readJSON = async (path) => JSON.parse(await readFile(new URL(path, import.meta.url), 'utf8'));
const readText = (path) => readFile(new URL(path, import.meta.url), 'utf8');

const spec = await readJSON('../contract/bridge/v1/spec.json');
const fixtures = await readJSON('../contract/bridge/v1/fixtures.json');

const route = (method, path) => spec.routes.find((item) => item.method === method && item.path === path);

function originAllowed(origin) {
  if (origin === undefined || spec.client.rejectOrigins.includes(origin)) return false;
  return spec.client.allowedOriginPrefixes.some((prefix) => origin.startsWith(prefix));
}

function requestAllowed(headers) {
  const host = headers.host?.toLowerCase();
  const allowedHosts = spec.transport.acceptedHostNames.map(
    (name) => `${name}:${spec.transport.defaultPort}`.toLowerCase(),
  );
  if (!host || !allowedHosts.includes(host)) return false;

  const origin = headers.origin;
  if (originAllowed(origin)) return true;
  return origin === undefined
    && spec.client.allowMissingOriginWithMarker
    && Boolean(headers[spec.client.markerHeader.toLowerCase()]);
}

function assertFields(object, fields, label) {
  for (const field of fields ?? []) {
    assert.ok(Object.hasOwn(object, field), `${label} must contain ${field}`);
  }
}

function assertEnums(object, enums, label) {
  for (const [field, values] of Object.entries(enums ?? {})) {
    if (Object.hasOwn(object, field)) {
      assert.ok(values.includes(object[field]), `${label}.${field} must be one of ${values.join(', ')}`);
    }
  }
}

test('contract has one unique definition for every v1 route', () => {
  assert.equal(spec.contract, 'mc-download-manager-bridge');
  assert.equal(spec.version, 1);
  assert.equal(spec.transport.bindHost, '127.0.0.1');
  assert.equal(spec.transport.defaultPort, 48213);

  const keys = spec.routes.map((item) => `${item.method} ${item.path}`);
  assert.equal(new Set(keys).size, keys.length);
  assert.deepEqual(new Set(keys), new Set([
    'GET /ping',
    'POST /download',
    'GET /downloads',
    'POST /action',
  ]));
});

for (const fixture of fixtures.authorizationCases) {
  test(`authorization fixture: ${fixture.name}`, () => {
    assert.equal(requestAllowed(fixture.headers), fixture.allowed);
  });
}

for (const fixture of fixtures.requests) {
  test(`request fixture: ${fixture.name}`, () => {
    const definition = route(fixture.method, fixture.path);
    assert.ok(definition, `unknown route ${fixture.method} ${fixture.path}`);
    assertFields(fixture.body, definition.requestRequired, fixture.name);
    assertEnums(fixture.body, definition.requestEnums, fixture.name);
    if (fixture.path === '/download') {
      const url = new URL(fixture.body.url);
      assert.ok(['http:', 'https:'].includes(url.protocol));
    }
  });
}

for (const fixture of fixtures.responses) {
  test(`response fixture: ${fixture.name}`, () => {
    const definition = route(fixture.method, fixture.path);
    assert.ok(definition, `unknown route ${fixture.method} ${fixture.path}`);
    assertFields(fixture.body, definition.responseRequired, fixture.name);
    if (fixture.path === '/downloads') {
      assert.ok(Array.isArray(fixture.body.items));
      for (const item of fixture.body.items) {
        assertFields(item, definition.itemRequired, `${fixture.name} item`);
        assertEnums(item, definition.itemEnums, `${fixture.name} item`);
      }
    }
  });
}

test('the WebExtension still targets the v1 port, routes, and marker header', async () => {
  const background = await readText('../Extension/background.js');
  const popup = await readText('../Extension/popup.js');
  assert.match(background, /DEFAULTS\s*=\s*\{\s*port:\s*48213\b/);
  assert.match(background, /['"]X-MCDM-Extension['"]/);
  for (const definition of spec.routes) assert.ok(background.includes(definition.path));
  for (const action of route('POST', '/action').requestEnums.action) {
    assert.ok(
      background.includes(`'${action}'`) || popup.includes(`'${action}'`),
      `extension must expose ${action}`,
    );
  }
});

test('the Swift bridge still implements the v1 routes and security inputs', async () => {
  const controller = await readText('../App/Sources/DownloadManager/Server/ServerController.swift');
  const server = await readText('../App/Sources/DownloadManager/Server/LocalServer.swift');
  const settings = await readText('../App/Sources/DownloadManager/Models/AppSettings.swift');

  assert.match(settings, /serverPort\s*=.*\?\?\s*48213\b/);
  assert.ok(server.includes('host: "127.0.0.1"'));
  assert.ok(controller.includes('req.headers["host"]'));
  assert.ok(controller.includes('req.headers["origin"]'));
  assert.ok(controller.includes('req.headers["x-mcdm-extension"]'));
  for (const prefix of spec.client.allowedOriginPrefixes) assert.ok(controller.includes(prefix));
  for (const definition of spec.routes) assert.ok(controller.includes(`"${definition.path}"`));
  for (const action of route('POST', '/action').requestEnums.action) {
    assert.ok(controller.includes(`case "${action}"`), `Swift bridge must implement ${action}`);
  }
});

test('the manifest grants only loopback HTTP hosts for bridge traffic', async () => {
  const manifest = await readJSON('../Extension/manifest.json');
  const bridgeHosts = manifest.host_permissions.filter((item) => item.startsWith('http://'));
  assert.deepEqual(new Set(bridgeHosts), new Set(['http://127.0.0.1/*', 'http://localhost/*']));
});

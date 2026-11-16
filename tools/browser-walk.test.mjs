import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Runs the deployed walk (tools/browser-walk.mjs with browser-pages.json) in
// PR CI against the committed site/public, so a page change that breaks the
// walk fails before it deploys. Retire with the walk.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pub = path.join(root, 'site/public');
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.json': 'application/json' };

async function serve(rewrite = html => html) {
  const seen = { writes: 0, reads: [] };
  const server = http.createServer((request, response) => {
    if (request.method !== 'GET') { seen.writes++; response.writeHead(200).end('saved'); return; }
    const url = new URL(request.url, 'http://fixture');
    seen.reads.push(url.pathname);
    const file = path.join(pub, url.pathname.endsWith('/') ? `${url.pathname}index.html` : url.pathname);
    if (!file.startsWith(pub + path.sep) || !fs.existsSync(file)) { response.writeHead(404).end(); return; }
    const type = types[path.extname(file)] ?? 'application/octet-stream';
    const body = fs.readFileSync(file);
    response.writeHead(200, { 'content-type': type }).end(type.startsWith('text/html') ? rewrite(body.toString(), url.pathname) : body);
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { origin: `http://127.0.0.1:${server.address().port}`, seen, close: () => new Promise(done => server.close(done)) };
}

async function walk(origin) {
  const child = spawn(process.execPath, ['tools/browser-walk.mjs'], { cwd: root, env: { ...process.env, VERIFY_URL: origin }, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.on('data', data => output += data);
  child.stderr.on('data', data => output += data);
  const [code] = await once(child, 'exit');
  const evidence = /Browser proof: (\S+);/.exec(output)?.[1];
  const result = evidence ? JSON.parse(fs.readFileSync(path.join(root, evidence, 'result.json'), 'utf8')) : null;
  return { code, output, evidence: evidence && path.join(root, evidence), result };
}

test('the committed pages pass the deployed walk and leave screenshots', async () => {
  const site = await serve();
  try {
    const run = await walk(site.origin);
    assert.equal(run.code, 0, run.output);
    const pages = JSON.parse(fs.readFileSync(path.join(root, 'browser-pages.json'), 'utf8')).pages.map(page => page.path);
    assert.deepEqual(run.result.pages.map(page => [page.path, page.exitCode]), pages.map(page => [page, 0]));
    assert.equal(fs.readdirSync(run.evidence).filter(name => name.endsWith('.png')).length, pages.length);
    assert.equal(site.seen.writes, 0);
  } finally { await site.close(); }
});

test('a page that renders the wrong heading fails as wrong', async () => {
  const site = await serve((html, page) => page === '/privacy/' ? html.replace('<h1>Privacy Policy</h1>', '<h1>Page moved</h1>') : html);
  try {
    const run = await walk(site.origin);
    assert.equal(run.code, 1, run.output);
    assert.ok(run.result.pages.some(page => page.path === '/privacy/' && page.problems.includes('Wrong rendered text at h1')), run.output);
  } finally { await site.close(); }
});

test('page and native writes are refused before they reach the server', async () => {
  const attempt = '<form id="f" method="post" action="/save"></form><script>'
    + 'fetch("/save",{method:"POST"}).catch(()=>{});navigator.sendBeacon("/save","x");'
    + 'HTMLFormElement.prototype.submit.call(document.getElementById("f"));</script>';
  const site = await serve((html, page) => page === '/' ? html.replace('</body>', `${attempt}</body>`) : html);
  try {
    const run = await walk(site.origin);
    assert.equal(run.code, 1, run.output);
    assert.ok(run.result.pages.some(page => page.blockedWrite), run.output);
    assert.equal(site.seen.writes, 0, 'a write reached the server');
  } finally { await site.close(); }
});

test('cross-origin reads keep the browser\'s native CORS outcome', async () => {
  let allow = false;
  const calls = [];
  const other = http.createServer((request, response) => {
    calls.push(request.method);
    response.setHeader('access-control-allow-origin', '*');
    response.setHeader('access-control-allow-headers', 'x-product-header');
    response.writeHead(request.method === 'OPTIONS' ? (allow ? 204 : 403) : 200).end('read');
  });
  other.listen(0, '127.0.0.1');
  await once(other, 'listening');
  const read = `<script>fetch("http://127.0.0.1:${other.address().port}/read",{headers:{"x-product-header":"1"}}).catch(()=>{})</script>`;
  const site = await serve((html, page) => page === '/' ? html.replace('</body>', `${read}</body>`) : html);
  try {
    const refused = await walk(site.origin);
    assert.notEqual(refused.code, 0, refused.output);
    assert.ok(calls.includes('OPTIONS') && !calls.includes('GET'), 'a refused preflight must stop the read');
    allow = true; calls.length = 0;
    const allowed = await walk(site.origin);
    assert.equal(allowed.code, 0, allowed.output);
    assert.ok(calls.includes('OPTIONS') && calls.includes('GET'), 'an allowed preflight must permit the read');
  } finally { await site.close(); await new Promise(done => other.close(done)); }
});

test('an unreachable site is unavailable, not wrong', async () => {
  const site = await serve();
  const { origin } = site;
  await site.close();
  const run = await walk(origin);
  assert.equal(run.code, 3, run.output);
});

#!/usr/bin/env node
import fs from 'node:fs';
import { installReadOnlyBrowser, probeUserAgent, installNativeWriteGuard } from './read-only-browser.js';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const root = process.cwd();
const evidence = path.join(root, '.context/verification', `browser-${Date.now()}-${process.pid}`);
const result = { dirty: Boolean(execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim()), source: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(), pages: [] };
let browser, exitCode = 3;
try {
  fs.mkdirSync(evidence, { recursive: true });
  const base = new URL(process.env.VERIFY_URL);
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search) throw new Error('VERIFY_URL must be an HTTP origin without credentials or query');
  result.baseUrl = base.origin;
  const config = JSON.parse(fs.readFileSync('browser-pages.json', 'utf8'));
  const pages = config.pages;
  if (!Array.isArray(pages) || !pages.length) throw new Error('No browser pages configured');
  for (const page of pages) {
    if (!page.path?.startsWith('/') || /[?#]/.test(page.path) || new URL(page.path, base).origin !== base.origin || !page.assertions?.length || page.assertions.some(a => !a.selector || typeof a.text !== 'string' || !a.text)) throw new Error('Each page needs a same-origin path and nonempty selector/text assertions');
  }
  const expectedSha = process.env.EXPECTED_DEPLOYED_SHA;
  const readVersion = async () => {
    const response = await fetch(new URL(config.versionPath, base), { headers: { 'x-biv-live-check': '1' }, redirect: 'error', signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error('Deployed revision unavailable');
    const data = await response.json();
    if (!/^[0-9a-f]{40}$/.test(data.sha)) throw new Error('Deployed revision invalid');
    return data.sha;
  };
  if (expectedSha) {
    if (!/^[0-9a-f]{40}$/.test(expectedSha) || !config.versionPath?.startsWith('/') || new URL(config.versionPath, base).origin !== base.origin) throw new Error('Configure the deployed version path and exact expected SHA');
    result.deployed = await readVersion();
    if (result.deployed !== expectedSha) { result.wrong = 'Deployed revision does not match the checked artifact'; throw new Error('Wrong deployment'); }
  }
  const require = createRequire(import.meta.url);
  const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
  browser = await chromium.launch({ headless: true, args: ['--block-new-web-contents'] });
  const userAgent = await probeUserAgent(browser);
  exitCode = 0;
  for (const [index, spec] of pages.entries()) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      const observation = { path: spec.path, attempt, problems: [], unavailable: [] };
      const context = await browser.newContext({ storageState: { cookies: [], origins: [] }, userAgent, serviceWorkers: 'block', viewport: { width: spec.width || 1440, height: 900 } });
      let page, loaded = false;
      try {
        const onViolation = record => {
          if (!record.unavailable) observation.blockedWrite = true;
          if (record.unavailable) observation.blockedCapability = true;
          (record.unavailable ? observation.unavailable : observation.problems).push(`Refused ${record.api} ${record.path}`);
        };
        await context.exposeBinding('bivReadOnlyViolation', (_source, record) => onViolation(record));
        await context.addInitScript(installReadOnlyBrowser, { reportName: 'bivReadOnlyViolation', telemetry: [{ path: '/cdn-cgi/rum', hostnameSuffix: '' }] });
        page = await context.newPage();
        await installNativeWriteGuard(page, onViolation);
        page.on('pageerror', () => observation.problems.push('Page JavaScript error'));
        page.on('console', message => {
          if (message.type() !== 'error') return;
          (/^Failed to load resource: net::ERR_/.test(message.text()) ? observation.unavailable : observation.problems).push('Browser console error');
        });
        page.on('response', response => {
          if ([401, 403, 407].includes(response.status())) { observation.accessRefused = true; observation.unavailable.push('Browser access refused'); }
          else if (response.status() >= 400) observation.problems.push(`HTTP ${response.status()}`);
        });
        page.on('requestfailed', () => observation.unavailable.push('Required browser request failed'));
        const response = await page.goto(new URL(spec.path, base).href, { waitUntil: 'load', timeout: 15000 });
        if (!response) throw new Error('Navigation returned no document');
        if ([401, 403, 407].includes(response.status())) throw new Error('Browser access refused');
        if (new URL(page.url()).origin !== base.origin) { observation.foreignDocument = true; throw new Error('Configured origin did not supply the document'); }
        loaded = true;
        if (response.status() !== 200) observation.problems.push(`Document HTTP ${response.status()}`);
        for (const assertion of spec.assertions) {
          const locator = page.locator(assertion.selector);
          await locator.waitFor({ state: 'visible', timeout: 3000 });
          await page.waitForFunction(selector => document.querySelector(selector)?.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }), assertion.selector, { timeout: 3000 });
          if (!(await locator.innerText()).includes(assertion.text)) observation.problems.push(`Wrong rendered text at ${assertion.selector}`);
        }
        await page.waitForTimeout(250);
        if (new URL(page.url()).origin !== base.origin) { observation.foreignDocument = true; throw new Error('Document left the configured origin'); }
      } catch (error) {
        (loaded && error.name === 'TimeoutError' && !observation.unavailable.length ? observation.problems : observation.unavailable).push(loaded ? 'Required rendered state missing' : 'Browser observation unavailable');
      } finally {
        try { if (page) await page.screenshot({ path: path.join(evidence, `page-${index + 1}-attempt-${attempt}.png`), fullPage: true }); }
        catch { observation.unavailable.push('Screenshot unavailable'); }
        try { await context.close(); } catch { observation.unavailable.push('Browser context cleanup failed'); }
      }
      observation.exitCode = observation.blockedWrite ? 1 : observation.accessRefused || observation.foreignDocument || observation.blockedCapability ? 3 : observation.problems.length ? 1 : observation.unavailable.length ? 3 : 0;
      result.pages.push(observation);
      if (observation.exitCode === 1 && attempt === 1) continue;
      if (observation.exitCode === 1) exitCode = 1;
      else if (observation.exitCode === 3 && exitCode === 0) exitCode = 3;
      break;
    }
  }
  if (expectedSha) {
    result.deployedAfter = await readVersion();
    if (result.deployedAfter !== expectedSha) { result.wrong = 'Deployment changed during the browser walk'; throw new Error('Wrong deployment'); }
  }

} catch (error) {
  result.unavailable = error.message;
  exitCode = result.wrong || exitCode === 1 ? 1 : 3;
} finally {
  try { await browser?.close(); } catch { if (exitCode === 0) exitCode = 3; }
}
result.exitCode = exitCode;
try { fs.writeFileSync(path.join(evidence, 'result.json'), JSON.stringify(result, null, 2) + '\n'); }
catch {
  if (exitCode === 0) exitCode = 3;
  result.exitCode = exitCode;
  result.unavailable = 'Browser result evidence unavailable';
  console.error(JSON.stringify(result));
}
console.log(`Browser proof: ${path.relative(root, evidence)}; exit ${exitCode}`);
process.exitCode = exitCode;

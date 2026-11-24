#!/usr/bin/env node
// Checks the windowshepherd.com page in Chromium (never Chrome).
// Usage: node site/tests/check-page.cjs            (serves site/ on 127.0.0.1:8742)
//        BASE=https://windowshepherd.com node site/tests/check-page.cjs   (checks a live URL)
// Prints ok/FAIL per check and exits 1 on any FAIL. Screenshots go to site/tests/.shots/.
const { chromium } = require('/opt/homebrew/lib/node_modules/@playwright/cli/node_modules/playwright-core');
const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const path = require('path');

const SITE = path.resolve(__dirname, '..');
const SHOTS = path.join(__dirname, '.shots');
const PORT = 8742;
const BASE = process.env.BASE || `http://127.0.0.1:${PORT}`;
const VIEWPORTS = [{ name: 'desktop', width: 1440, height: 900 }, { name: 'phone', width: 360, height: 740 }];
const GH = 'https://github.com/cabaynes/window-shepherd';

// Each check: { name, run({ page, vp, browser, open }) → true | string (why it failed) }.
// `per: 'viewport'` runs it at every viewport on the shared page; `per: 'once'` runs it once
// with `open(options)` for its own fresh page. Later tasks append here.
const checks = [];

checks.push({ name: 'no horizontal scroll', per: 'viewport', run: async ({ page }) => {
  const { sw, iw } = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, iw: innerWidth }));
  return sw <= iw || `scrollWidth ${sw} > ${iw}`;
}});

checks.push({ name: 'no requests leave the site', per: 'viewport', run: async ({ requests }) => {
  const origin = new URL(BASE).origin;
  const outside = requests.filter(u => !u.startsWith(origin) && !u.startsWith('data:'));
  return outside.length === 0 || outside.join(', ');
}});

checks.push({ name: 'no console errors', per: 'viewport', run: async ({ errors }) => errors.length === 0 || errors.join(' | ') });

checks.push({ name: 'Bungee Shade loaded', per: 'viewport', run: async ({ page }) => {
  // fonts.check() is true when no such face is declared at all, so look for the loaded face itself.
  const ok = await page.evaluate(async () => {
    await document.fonts.load('16px "Bungee Shade"');
    return [...document.fonts].some(f => f.family.replace(/["']/g, '') === 'Bungee Shade' && f.status === 'loaded');
  });
  return ok || 'font not loaded';
}});

checks.push({ name: 'sections in order', per: 'viewport', run: async ({ page }) => {
  const want = ['hero', 'demo', 'replug', 'tidy', 'story', 'start', 'rectangle', 'trust', 'faq', 'footer'];
  const got = await page.evaluate(sel => sel.map(s => {
    const el = s === 'footer' ? document.querySelector('footer') : document.getElementById(s);
    return el ? el.getBoundingClientRect().top + scrollY : null;
  }), want);
  const missing = want.filter((_, i) => got[i] === null);
  if (missing.length) return 'missing ' + missing.join(', ');
  for (let i = 1; i < got.length; i++) if (got[i] < got[i - 1]) return `${want[i]} before ${want[i - 1]}`;
  return true;
}});

checks.push({ name: 'no unverified claims', per: 'viewport', run: async ({ page }) => {
  const text = await page.evaluate(() => document.body.innerText);
  const bad = ['[verify', '[Charles', 'identical monitors are kept apart', 'Intel', '[month]'].filter(t => text.includes(t));
  return bad.length === 0 || 'found ' + bad.join(', ');
}});

checks.push({ name: 'coming-soon button', per: 'viewport', run: async ({ page }) => {
  const b = await page.evaluate(() => { const a = document.getElementById('get'); return a && { t: a.innerText.trim(), h: a.href }; });
  if (!b) return 'no #get';
  return (b.t === 'Watch for the release on GitHub' && b.h.startsWith(GH)) || JSON.stringify(b);
}});

checks.push({ name: 'symbols taught once', per: 'viewport', run: async ({ page }) => {
  const text = await page.evaluate(() => document.body.innerText);
  const n = text.split('⌃ is Control, ⌥ is Option, ⌘ is Command, ⇧ is Shift').length - 1;
  return n === 1 || `appears ${n} times`;
}});

module.exports = { checks };

async function serve() {
  if (process.env.BASE) return null;
  const server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1'], { cwd: SITE, stdio: 'ignore' });
  for (let i = 0; i < 50; i++) {
    const up = await new Promise(res => http.get(BASE + '/', r => { r.resume(); res(r.statusCode === 200); }).on('error', () => res(false)));
    if (up) return server;
    await new Promise(r => setTimeout(r, 200));
  }
  server.kill();
  throw new Error('server did not start');
}

async function main() {
  fs.mkdirSync(SHOTS, { recursive: true });
  const server = await serve();
  const browser = await chromium.launch();
  let failed = 0;
  const report = (name, r) => {
    if (r === true) console.log('ok   ' + name);
    else { failed++; console.log('FAIL ' + name + ': ' + r); }
  };
  async function open(options = {}) {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, ...options });
    const page = await ctx.newPage();
    const requests = [], errors = [];
    page.on('request', r => requests.push(r.url()));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto(BASE + '/', { waitUntil: 'load' });
    return { ctx, page, requests, errors };
  }
  try {
    for (const vp of VIEWPORTS) {
      const o = await open({ viewport: { width: vp.width, height: vp.height }, hasTouch: vp.width < 500 });
      await o.page.evaluate(() => document.fonts.ready);
      for (const c of checks.filter(c => c.per === 'viewport')) {
        let r;
        try { r = await c.run({ ...o, vp, browser, open }); } catch (e) { r = String(e.message || e).split('\n')[0]; }
        report(`${c.name} (${vp.name})`, r);
      }
      await o.page.screenshot({ path: path.join(SHOTS, `${vp.name}.png`), fullPage: true });
      await o.ctx.close();
    }
    for (const c of checks.filter(c => c.per === 'once')) {
      let r;
      try { r = await c.run({ browser, open }); } catch (e) { r = String(e.message || e).split('\n')[0]; }
      report(c.name, r);
    }
  } finally {
    await browser.close();
    if (server) server.kill();
  }
  console.log(failed ? `${failed} FAILED` : 'all ok');
  process.exit(failed ? 1 : 0);
}

if (require.main === module) main().catch(e => { console.error(e); process.exit(1); });

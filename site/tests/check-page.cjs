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
  const bad = ['[verify', '[Charles', 'identical monitors are kept apart', 'Intel', '[month]', 'full screen apps'].filter(t => text.includes(t));
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

// ---------- the demo ----------
// Where each window is drawn vs. where the model says it is, in px, from the screen's display box.
const placement = page => page.evaluate(() => {
  const d = window.__demo;
  if (!d) return null;
  const box = n => document.querySelector(`[data-display="${n}"]`).getBoundingClientRect();
  return d.state.windows.map(w => {
    const r = document.querySelector(`[data-win="${w.id}"]`).getBoundingClientRect();
    const b = box(w.at.screen);
    return { id: w.id, screen: w.at.screen, r: { x: r.left, y: r.top, w: r.width, h: r.height },
      want: { x: b.left + w.at.x * b.width, y: b.top + w.at.y * b.height, w: w.at.w * b.width, h: w.at.h * b.height },
      laptop: (() => { const l = box(1); return { x: l.left, y: l.top, w: l.width, h: l.height }; })() };
  });
});
const off = p => ['x', 'y', 'w', 'h'].map(k => Math.abs(p.r[k] - p.want[k])).reduce((a, b) => Math.max(a, b));
const where = ps => ps.filter(p => off(p) > 2).map(p => `${p.id} off by ${off(p).toFixed(1)}px`).join(', ');
const settled = page => page.evaluate(() => window.__demo.settled);
const clickPlug = page => page.click('[data-plug]');
const noAutoplay = { reducedMotion: 'no-preference' };
// A fresh page whose automatic replug has been stopped by a click that changes nothing.
async function quietPage(open, options = {}) {
  const o = await open({ ...noAutoplay, ...options });
  await o.page.waitForFunction(() => window.__demo);
  await o.page.click('[data-scope="window"]');
  return o;
}

checks.push({ name: 'unplug piles every window onto the laptop', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await clickPlug(page); await settled(page);
  const ps = await placement(page);
  await ctx.close();
  const outside = ps.filter(p => p.screen !== 1 || p.r.x < p.laptop.x - 1 || p.r.y < p.laptop.y - 1
    || p.r.x + p.r.w > p.laptop.x + p.laptop.w + 1 || p.r.y + p.r.h > p.laptop.y + p.laptop.h + 1);
  return outside.length === 0 || 'outside the laptop: ' + outside.map(p => p.id).join(', ');
}});

checks.push({ name: 'plug in brings every window home', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await clickPlug(page); await settled(page);
  await clickPlug(page); await settled(page);
  const ps = await placement(page);
  const home = await page.evaluate(() => window.__demo.state.windows.every(w =>
    ['screen', 'x', 'y', 'w', 'h'].every(k => w.at[k] === w.home[k])));
  const caption = await page.textContent('.caption');
  await ctx.close();
  if (!home) return 'model not home';
  if (where(ps)) return where(ps);
  return caption.includes('Window Shepherd') || 'caption: ' + caption;
}});

checks.push({ name: 'rapid clicks end in the last click\'s state', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  for (let i = 0; i < 4; i++) await clickPlug(page, { delay: 0 });
  await settled(page);
  const ps = await placement(page);
  const plugged = await page.evaluate(() => window.__demo.state.plugged);
  await ctx.close();
  if (!plugged) return 'not plugged in after 4 clicks';
  return !where(ps) || where(ps);
}});

checks.push({ name: 'other screen disabled while unplugged', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await clickPlug(page); await settled(page);
  const r = await page.evaluate(() => {
    const b = document.querySelector('[data-action="other"]');
    const why = document.getElementById(b.getAttribute('aria-describedby') || '');
    const ink = c => getComputedStyle(c).color;
    return { disabled: b.disabled, why: why ? why.textContent : '', color: ink(b.querySelector('.action-name')) };
  });
  await ctx.close();
  // CLAUDE.md: nothing the user reads is drawn faint/disabled grey.
  return (r.disabled && /plug/i.test(r.why) && r.color === 'rgb(0, 0, 0)') || JSON.stringify(r);
}});

checks.push({ name: 'scope toggle is keyboard-usable', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await page.focus('[data-scope="window"]');
  await page.keyboard.press('Tab');
  const focused = await page.evaluate(() => document.activeElement.dataset.scope);
  await page.keyboard.press('Space');
  const pressed = await page.getAttribute('[data-scope="app"]', 'aria-pressed');
  await ctx.close();
  return (focused === 'app' && pressed === 'true') || `focused ${focused}, aria-pressed ${pressed}`;
}});

checks.push({ name: 'an action moves windows and shows its keys', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await page.click('[data-scope="app"]');
  const keys = await page.textContent('[data-action="ninety"] kbd');
  await page.click('[data-action="ninety"]'); await settled(page);
  const ps = await placement(page);
  await ctx.close();
  if (keys.trim() !== '⌃⌥⌘G') return 'keys ' + keys;
  return !where(ps) || where(ps);
}});

checks.push({ name: 'autoplay yields to a click', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open(noAutoplay);
  await page.waitForFunction(() => window.__demo);
  await page.click('[data-scope="everything"]');
  await page.waitForTimeout(4000);
  const moved = await page.evaluate(() => !window.__demo.state.plugged
    || window.__demo.state.windows.some(w => ['screen', 'x', 'y'].some(k => w.at[k] !== w.home[k])));
  await ctx.close();
  return !moved || 'windows moved after the visitor clicked';
}});

checks.push({ name: 'autoplay waits until the demo is in view, then replugs once', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open(noAutoplay);
  await page.waitForFunction(() => window.__demo);
  const below = await page.evaluate(() => document.querySelector('[data-demo]').getBoundingClientRect().top > innerHeight * .5);
  await page.waitForTimeout(3000);
  const early = await page.evaluate(() => !window.__demo.state.plugged);
  await page.evaluate(() => document.querySelector('[data-demo]').scrollIntoView({ block: 'center' }));
  const sawUnplug = await page.waitForFunction(() => !window.__demo.state.plugged, null, { timeout: 4000 }).then(() => true, () => false);
  await page.waitForFunction(() => window.__demo.state.plugged, null, { timeout: 8000 }).catch(() => {});
  await settled(page);
  const ps = await placement(page);
  await ctx.close();
  if (below && early) return 'played before the demo was in view';
  if (!sawUnplug) return 'never unplugged by itself once in view';
  return !where(ps) || where(ps);
}});

checks.push({ name: 'reduced motion: no autoplay, moves are instant', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open({ reducedMotion: 'reduce' });
  await page.waitForFunction(() => window.__demo);
  await page.waitForTimeout(2500);
  const stillPlugged = await page.evaluate(() => window.__demo.state.plugged);
  await clickPlug(page);
  await page.evaluate(() => new Promise(requestAnimationFrame));
  const ps = await placement(page);
  await ctx.close();
  if (!stillPlugged) return 'autoplayed under reduced motion';
  return !where(ps) || 'not instant: ' + where(ps);
}});

checks.push({ name: 'each app has its own title-bar tint', per: 'viewport', run: async ({ page }) => {
  await page.waitForFunction(() => window.__demo);
  const bars = await page.evaluate(() => [...document.querySelectorAll('[data-win]')].map(w => ({
    app: w.dataset.app, bg: getComputedStyle(w.querySelector('.win-bar')).backgroundColor })));
  const byApp = {};
  for (const b of bars) (byApp[b.app] ||= new Set()).add(b.bg);
  const unfocused = await page.evaluate(() => [...document.querySelectorAll('[data-win]:not(.is-focused)')].map(w => ({
    app: w.dataset.app, bg: getComputedStyle(w.querySelector('.win-bar')).backgroundColor })));
  const colours = {};
  for (const u of unfocused) (colours[u.app] ||= new Set()).add(u.bg);
  const tints = Object.values(colours).map(c => [...c][0]);
  if (Object.values(colours).some(c => c.size > 1)) return 'one app, several tints: ' + JSON.stringify(Object.fromEntries(Object.entries(colours).map(([k, v]) => [k, [...v]])));
  return new Set(tints).size === tints.length || 'apps share a tint: ' + JSON.stringify(Object.fromEntries(Object.entries(colours).map(([k, v]) => [k, [...v]])));
}});

// Charles, 2026-11-24: the text above and below the demo runs at least as wide as the demo.
checks.push({ name: 'text column as wide as the demo', per: 'viewport', run: async ({ page }) => {
  const r = await page.evaluate(() => {
    const w = sel => document.querySelector(sel).getBoundingClientRect();
    const stage = w('[data-demo]');
    return { stage: Math.round(stage.width), left: Math.round(stage.left),
      cols: ['.lede', '#replug > p', '#faq', '.footer p'].map(sel => ({ sel, w: Math.round(w(sel).width), l: Math.round(w(sel).left) })) };
  });
  const narrow = r.cols.filter(c => c.w < r.stage - 1 || Math.abs(c.l - r.left) > 1);
  return narrow.length === 0 || `demo ${r.stage}px at ${r.left}: ` + narrow.map(c => `${c.sel} ${c.w}px at ${c.l}`).join(', ');
}});

// ---------- icons and link preview ----------
checks.push({ name: 'icons exist', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open(noAutoplay);
  const hrefs = await page.evaluate(() => [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')].map(l => l.href));
  const bad = [];
  for (const h of [...hrefs, new URL('favicon.ico', BASE + '/').href]) {   // the site may sit under a path (github.io)
    const r = await page.request.get(h);
    if (r.status() !== 200 || !/^image\//.test(r.headers()['content-type'] || '')) bad.push(`${h} ${r.status()} ${r.headers()['content-type']}`);
  }
  await ctx.close();
  if (hrefs.length < 3) return `only ${hrefs.length} icon links`;
  return bad.length === 0 || bad.join(', ');
}});

checks.push({ name: 'link preview card', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open(noAutoplay);
  const og = await page.evaluate(() => Object.fromEntries([...document.querySelectorAll('meta[property^="og:"], meta[name^="twitter:"]')]
    .map(m => [m.getAttribute('property') || m.getAttribute('name'), m.content])));
  const img = og['og:image'] || '';
  let size = null;
  if (img) {
    const local = new URL(new URL(img).pathname.slice(1), BASE + '/').href;   // the file this copy of the site serves
    size = await page.evaluate(async src => { const i = new Image(); i.src = src; await i.decode(); return [i.naturalWidth, i.naturalHeight]; }, local);
  }
  await ctx.close();
  if (!img.startsWith('https://windowshepherd.com/')) return 'og:image not absolute: ' + img;
  if (!og['og:title'] || !og['og:description'] || og['twitter:card'] !== 'summary_large_image') return JSON.stringify(og);
  return (size && size[0] === 1200 && size[1] === 630) || 'og.png size ' + size;
}});

checks.push({ name: 'search engines: robots, sitemap, structured data', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await open(noAutoplay);
  const robots = await page.request.get(new URL('robots.txt', BASE + '/').href);
  const sitemap = await page.request.get(new URL('sitemap.xml', BASE + '/').href);
  const robotsText = robots.status() === 200 ? await robots.text() : '';
  const sitemapText = sitemap.status() === 200 ? await sitemap.text() : '';
  const { ld, canonical } = await page.evaluate(() => ({
    ld: [...document.querySelectorAll('script[type="application/ld+json"]')].map(s => s.textContent),
    canonical: document.querySelector('link[rel="canonical"]')?.href,
  }));
  await ctx.close();
  if (!/^Sitemap: https:\/\/windowshepherd\.com\/sitemap\.xml$/m.test(robotsText)) return 'robots.txt ' + robots.status() + ' lacks the sitemap line';
  if (/^Disallow: *\/\s*$/m.test(robotsText)) return 'robots.txt blocks the whole site';
  if (!sitemapText.includes(`<loc>${canonical}</loc>`)) return 'sitemap.xml ' + sitemap.status() + ' lacks ' + canonical;
  if (ld.length !== 1) return `${ld.length} structured-data blocks`;
  let graph;
  try { graph = JSON.parse(ld[0])['@graph']; } catch (e) { return 'structured data is not valid JSON: ' + e.message; }
  const app = (graph || []).find(n => n['@type'] === 'SoftwareApplication');
  if (!app) return 'no SoftwareApplication';
  if (app.url !== canonical || app.offers?.price !== '0' || !app.operatingSystem) return JSON.stringify(app);
  // Nothing the release hasn't made true yet: no download, version, size or ratings.
  const early = ['downloadUrl', 'softwareVersion', 'fileSize', 'aggregateRating', 'review'].filter(k => k in app);
  return early.length === 0 || 'claims before release: ' + early.join(', ');
}});

checks.push({ name: 'a cancelled animation still settles', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  const done = await page.evaluate(async () => {
    document.querySelector('[data-plug]').click();
    const first = window.__demo.settled.then(() => true);
    document.querySelector('[data-plug]').click();   // cuts the first run short
    return Promise.race([first, new Promise(r => setTimeout(() => r(false), 1500))]);
  });
  await ctx.close();
  return done || 'the first run\'s settled promise never resolved';
}});

checks.push({ name: 'no shortcut shown on the disabled button', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await clickPlug(page); await settled(page);
  const keys = await page.textContent('[data-action="other"] kbd');
  await clickPlug(page); await settled(page);
  const back = await page.textContent('[data-action="other"] kbd');
  await ctx.close();
  return (keys === '' && back !== '') || `unplugged "${keys}", plugged "${back}"`;
}});

checks.push({ name: 'toy windows have unique names and say which is selected', per: 'once', run: async ({ open }) => {
  const { page, ctx } = await quietPage(open);
  await page.click('[data-win="code-2"]');
  const r = await page.evaluate(() => {
    const wins = [...document.querySelectorAll('[data-win]')];
    return { names: wins.map(w => w.getAttribute('aria-label')),
      pressed: wins.filter(w => w.getAttribute('aria-pressed') === 'true').map(w => w.dataset.win),
      caption: document.querySelector('.caption').textContent };
  });
  await ctx.close();
  if (new Set(r.names).size !== r.names.length) return 'duplicate names: ' + r.names.join(', ');
  if (r.pressed.join() !== 'code-2') return 'aria-pressed on: ' + r.pressed.join();
  return /selected/i.test(r.caption) || 'caption: ' + r.caption;
}});

checks.push({ name: 'footer names ChaCha Ventures', per: 'viewport', run: async ({ page }) => {
  const t = await page.textContent('footer');
  return /© 20\d\d ChaCha Ventures/.test(t) || 'footer: ' + t.slice(0, 120);
}});

// Charles, 2026-11-24 (on his phone): the shortcut ladder and the demo's buttons wrapped badly.
checks.push({ name: 'shortcut ladder: each key sits on its line', per: 'viewport', run: async ({ page }) => {
  const off = await page.evaluate(() => [...document.querySelectorAll('.ladder li')].map(li => {
    const k = li.querySelector(':scope > kbd').getBoundingClientRect(), t = li.querySelector('span').getBoundingClientRect();
    return Math.abs(k.top - t.top) < k.height && t.left > k.right - 1;
  }));
  return off.every(Boolean) || 'keys on their own line: ' + off.map((ok, i) => ok ? null : i + 1).filter(Boolean).join(', ');
}});

checks.push({ name: 'demo buttons in tidy rows', per: 'viewport', run: async ({ page }) => {
  const r = await page.evaluate(() => {
    const rows = sel => new Set([...document.querySelectorAll(sel)].map(b => Math.round(b.getBoundingClientRect().top))).size;
    const wrapped = [...document.querySelectorAll('.scope, .action, .plug')].filter(b => {
      const lh = parseFloat(getComputedStyle(b).lineHeight) || 20;
      return b.querySelector('.action-name, :scope') && b.clientHeight > lh * 2.2;
    }).map(b => b.textContent.trim());
    return { scope: rows('.scope'), actions: rows('.action'), wrapped, narrow: innerWidth < 600 };
  });
  if (r.scope !== 1) return `scope buttons on ${r.scope} rows`;
  if (r.actions > (r.narrow ? 2 : 1)) return `action buttons on ${r.actions} rows`;
  return r.wrapped.length === 0 || 'text wraps inside: ' + r.wrapped.join(', ');
}});

// Charles: on a phone you can't tell how much page is left. Dots down the side show where you are.
checks.push({ name: 'section dots show where you are', per: 'viewport', run: async ({ page }) => {
  const dots = await page.$$eval('nav.dots a', as => as.map(a => a.getAttribute('href')));
  if (dots.length < 7) return `${dots.length} dots`;
  await page.evaluate(() => document.getElementById('faq').scrollIntoView({ block: 'start', behavior: 'instant' }));
  await page.waitForTimeout(400);
  const r = await page.evaluate(() => {
    const cur = document.querySelector('nav.dots a[aria-current="true"]');
    const nav = document.querySelector('nav.dots').getBoundingClientRect();
    const text = document.querySelector('#faq').getBoundingClientRect();
    return { cur: cur && cur.getAttribute('href'), visible: nav.width > 0 && nav.right <= innerWidth, clear: nav.left >= text.right - 1 };
  });
  await page.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
  if (r.cur !== '#faq') return 'current dot: ' + r.cur;
  if (!r.visible) return 'dots not visible';
  return r.clear || 'dots overlap the text';
}});

// A new page must never pair with an old stylesheet or script still cached (Charles's phone,
// 2026-11-24: Pages caches 10 minutes). Every local CSS/JS address carries ?v=<version>, which
// the publish workflow stamps with the commit (it's "dev" locally).
checks.push({ name: 'stylesheets and scripts are versioned', per: 'once', run: async ({ open }) => {
  const { page, ctx, requests } = await open(noAutoplay);
  await page.waitForFunction(() => window.__demo);
  await ctx.close();
  const origin = new URL(BASE).origin;
  const assets = requests.filter(u => u.startsWith(origin) && /\.(css|js)(\?|$)/.test(u));
  const unversioned = assets.filter(u => !/\?v=[0-9a-z]+$/.test(u));
  if (assets.length < 4) return 'only ' + assets.join(', ');
  if (unversioned.length) return 'no version: ' + unversioned.join(', ');
  const versions = new Set(assets.map(u => u.split('?v=')[1]));
  if (versions.size !== 1) return 'mixed versions: ' + [...versions].join(', ');
  if (process.env.BASE && versions.has('dev')) return 'published copy is not stamped';
  return true;
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
    page.setDefaultTimeout(8000);
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

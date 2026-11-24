#!/usr/bin/env node
// Renders site/tests/og-card.html to site/og.png (1200×630) in Chromium.
// Run python3 -I scripts/site-icons.py first (it writes the card's icon).
const { chromium } = require('/opt/homebrew/lib/node_modules/@playwright/cli/node_modules/playwright-core');
const { spawn } = require('child_process');
const path = require('path');

const SITE = path.resolve(__dirname, '..');
const PORT = 8744;

(async () => {
  // Served over HTTP: a file:// page is refused the font fetch.
  const server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1'], { cwd: SITE, stdio: 'ignore' });
  await new Promise(r => setTimeout(r, 800));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
    await page.goto(`http://127.0.0.1:${PORT}/tests/og-card.html`);
    // Wait on the face itself: fonts.ready can resolve before it's requested.
    await page.evaluate(() => document.fonts.load('104px "Bungee Shade"'));
    await page.evaluate(() => document.querySelector('img').decode());
    await page.screenshot({ path: path.join(SITE, 'og.png') });
    console.log('wrote site/og.png');
  } finally {
    await browser.close();
    server.kill();
  }
})();

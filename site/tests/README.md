# Site tests

- `node --test site/tests/*.test.mjs` — the demo model.
- `node site/tests/check-page.cjs` — the page in Chromium at desktop and phone width (serves `site/` itself; `BASE=https://windowshepherd.com` checks the live site). Screenshots land in `site/tests/.shots/` (gitignored).

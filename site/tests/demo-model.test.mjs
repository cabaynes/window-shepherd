// Run: node --test site/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createDemo, unplug, plugIn, act, focus, shortcutFor } from '../demo-model.js';

const byId = (s, id) => s.windows.find(w => w.id === id);
const same = (a, b) => ['screen', 'x', 'y', 'w', 'h'].every(k => Math.abs(a[k] - b[k]) < 1e-9);
const allHome = s => s.windows.every(w => same(w.at, w.home));

test('createDemo has six windows, four on the monitor', () => {
  const s = createDemo();
  assert.equal(s.windows.length, 6);
  assert.equal(s.windows.filter(w => w.at.screen === 2).length, 4);
  assert.equal(s.plugged, true);
  assert.ok(allHome(s));
});

test('unplug puts every window on the laptop, inside it', () => {
  const s = createDemo();
  const steps = unplug(s);
  assert.equal(steps.length, 1);
  assert.equal(s.plugged, false);
  for (const w of s.windows) {
    assert.equal(w.at.screen, 1, w.id);
    assert.ok(w.at.x >= 0 && w.at.y >= 0 && w.at.x + w.at.w <= 1 + 1e-9 && w.at.y + w.at.h <= 1 + 1e-9, w.id);
  }
});

test('plugIn: macOS puts back exactly chrome-1 and messages, then Window Shepherd the rest', () => {
  const s = createDemo();
  unplug(s);
  const steps = plugIn(s);
  assert.equal(steps.length, 2);
  assert.equal(steps[0].who, 'macos');
  assert.deepEqual(steps[0].moves.map(m => m.id).sort(), ['chrome-1', 'messages']);
  assert.equal(steps[1].who, 'shepherd');
  assert.ok(steps[1].moves.length > 0);
  assert.ok(!steps[1].moves.some(m => m.id === 'chrome-1' || m.id === 'messages'));
  assert.equal(s.plugged, true);
  assert.ok(allHome(s));
});

test('rapid unplug then plug in ends home', () => {
  const s = createDemo();
  unplug(s); plugIn(s); unplug(s); plugIn(s);
  assert.ok(allHome(s));
});

test('act app ninety resizes both Chrome windows on their own screen', () => {
  const s = createDemo();
  focus(s, 'chrome-1');
  const r = act(s, 'app', 'ninety');
  assert.equal(r.keys, '⌃⌥⌘G');
  for (const id of ['chrome-1', 'chrome-2']) assert.ok(same(byId(s, id).at, { screen: 2, x: .05, y: .05, w: .9, h: .9 }), id);
  assert.ok(same(byId(s, 'notes').at, byId(s, 'notes').home), 'other apps untouched');
});

test('act all other sends everything to the screen opposite the focused window', () => {
  const s = createDemo();
  focus(s, 'notes');   // on the laptop, so the target is screen 2: 90% on a monitor
  const r = act(s, 'all', 'other');
  assert.equal(r.keys, '⌃⌥⌘2⇧');
  for (const w of s.windows) assert.ok(same(w.at, { screen: 2, x: .05, y: .05, w: .9, h: .9 }), w.id);
});

test('act app other sends every window of the app to one screen, full screen on the laptop', () => {
  const s = createDemo();
  focus(s, 'code-1');   // VS Code: code-1 on the monitor, code-2 on the laptop
  const r = act(s, 'app', 'other');
  assert.equal(r.keys, '⌃⌥⌘1');
  for (const id of ['code-1', 'code-2']) assert.ok(same(byId(s, id).at, { screen: 1, x: 0, y: 0, w: 1, h: 1 }), id);
  assert.ok(same(byId(s, 'chrome-1').at, byId(s, 'chrome-1').home), 'other apps untouched');
});

test('other-screen unavailable while unplugged', () => {
  const s = createDemo();
  unplug(s);
  const r = act(s, 'window', 'other');
  assert.ok(typeof r.error === 'string' && r.error.length > 0);
  assert.equal(r.steps.length, 0);
});

test('center keeps size', () => {
  const s = createDemo();
  focus(s, 'code-1');
  const before = { ...byId(s, 'code-1').at };
  act(s, 'window', 'center');
  const at = byId(s, 'code-1').at;
  assert.equal(at.w, before.w);
  assert.equal(at.h, before.h);
  assert.ok(Math.abs(at.x - (1 - at.w) / 2) < 1e-9 && Math.abs(at.y - (1 - at.h) / 2) < 1e-9);
});

test('shortcutFor covers the table', () => {
  assert.equal(shortcutFor('window', 'full', 1), '⌥⌘F');
  assert.equal(shortcutFor('window', 'ninety', 1), '⌥⌘G');
  assert.equal(shortcutFor('window', 'center', 1), '⌥⌘C');
  assert.equal(shortcutFor('window', 'other', 1), '⌥⌘2');
  assert.equal(shortcutFor('window', 'other', 2), '⌥⌘1');
  assert.equal(shortcutFor('app', 'full', 2), '⌃⌥⌘F');
  assert.equal(shortcutFor('app', 'ninety', 2), '⌃⌥⌘G');
  assert.equal(shortcutFor('app', 'center', 2), '⌃⌥⌘C');
  assert.equal(shortcutFor('app', 'other', 1), '⌃⌥⌘2');
  assert.equal(shortcutFor('all', 'full', 1), 'menu: Everything');
  assert.equal(shortcutFor('all', 'other', 1), '⌃⌥⌘2⇧');
  assert.equal(shortcutFor('all', 'other', 2), '⌃⌥⌘1⇧');
});

test('plug in restores the arrangement you had when you unplugged, not the starting one', () => {
  const s = createDemo();
  focus(s, 'chrome-1');
  act(s, 'app', 'ninety');
  const arranged = { ...byId(s, 'chrome-2').at };
  unplug(s); plugIn(s);
  assert.ok(same(byId(s, 'chrome-2').at, arranged));
});

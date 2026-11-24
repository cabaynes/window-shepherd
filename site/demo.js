// The playable replug demo: draws demo-model.js's state and animates its steps.
// The model is always already final; this file only decides how it looks getting there.
import { createDemo, unplug, plugIn, act, focus, shortcutFor } from './demo-model.js';

// Each screen's display area, in % of the stage. The device frames are drawn around these.
const DISPLAY = {
  1: { l: 2, t: 36, w: 34, h: 47 },    // laptop
  2: { l: 44, t: 3, w: 54, h: 70 },    // monitor
};
const MOVE_MS = 450, STAGGER_MS = 60, BETWEEN_STEPS_MS = 900, RING_MS = 700, AUTOPLAY_MS = 1500;

const root = document.getElementById('demo');
const stage = root.querySelector('[data-demo]');
const controls = root.querySelector('.controls');
const caption = root.querySelector('.caption');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

const state = createDemo();
let scope = 'window';
let timers = [];
let settle = Promise.resolve();
let visitorClicked = false;

const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k.startsWith('data-') || k.startsWith('aria-') || k === 'type' || k === 'id' || k === 'role') e.setAttribute(k, v);
    else e[k] = v;
  }
  e.append(...kids);
  return e;
};
const pct = n => n + '%';

// ---------- the scene ----------

function device(n) {
  const d = DISPLAY[n];
  const frame = el('div', { class: `device device-${n}`, 'aria-hidden': 'true' });
  Object.assign(frame.style, { left: pct(d.l), top: pct(d.t), width: pct(d.w), height: pct(d.h) });
  frame.append(el('div', { class: 'display', 'data-display': String(n) }));
  frame.append(el('div', { class: n === 1 ? 'laptop-base' : 'monitor-stand' }));
  return frame;
}

const cable = el('div', { class: 'cable', 'aria-hidden': 'true' });
cable.innerHTML = '<svg viewBox="0 0 100 20" preserveAspectRatio="none"><path class="cable-line" d="M0 2 C 40 2, 55 19, 100 19" /><path class="cable-loose" d="M0 2 C 14 2, 18 34, 28 40" /></svg>';
stage.append(device(1), device(2), cable);

const winEls = new Map();
for (const w of state.windows) {
  const b = el('button', { type: 'button', class: 'win', 'data-win': w.id, 'data-app': w.app, 'aria-label': `${w.label} window` },
    el('span', { class: 'win-bar' }, el('i'), el('i'), el('i'), el('span', { class: 'win-name' }, w.label)),
    el('span', { class: 'win-body' }));
  b.addEventListener('click', () => { visitor(); focus(state, w.id); paintFocus(); paintKeys(); });
  winEls.set(w.id, b);
  stage.append(b);
}

function place(w, at) {
  const d = DISPLAY[at.screen], e = winEls.get(w);
  e.style.left = pct(d.l + at.x * d.w);
  e.style.top = pct(d.t + at.y * d.h);
  e.style.width = pct(at.w * d.w);
  e.style.height = pct(at.h * d.h);
  e.dataset.screen = String(at.screen);
}

// Puts every window where the model says, without animating (the start of every action).
function jumpToState() {
  stage.classList.add('instant');
  for (const w of state.windows) {
    place(w.id, w.at);
    winEls.get(w.id).classList.remove('ring', 'landed');
  }
  void stage.offsetWidth;
  stage.classList.remove('instant');
}

function paintFocus() {
  for (const [id, e] of winEls) e.classList.toggle('is-focused', id === state.focused);
}

// ---------- the controls ----------

const plugBtn = el('button', { type: 'button', class: 'plug', 'data-plug': '' });
const scopes = [['window', 'This window'], ['app', 'All of Chrome'], ['everything', 'Everything']];
const scopeBtns = scopes.map(([key, label]) => el('button', { type: 'button', class: 'scope', 'data-scope': key, 'aria-pressed': String(key === scope) }, label));
const actions = [['full', 'Maximize'], ['ninety', '90%'], ['center', 'Center'], ['other', 'Other screen']];
const needsMonitor = el('p', { class: 'needs-monitor', id: 'needs-monitor' }, 'Moving to the other screen needs the monitor. Plug it back in first.');
const actionBtns = actions.map(([key, label]) => el('button', { type: 'button', class: 'action', 'data-action': key },
  el('span', { class: 'action-name' }, label), el('kbd')));

controls.append(
  el('div', { class: 'row row-plug' }, plugBtn),
  el('div', { class: 'row row-scope', role: 'group', 'aria-label': 'Which windows' }, ...scopeBtns),
  el('div', { class: 'row row-actions', role: 'group', 'aria-label': 'What to do with them' }, ...actionBtns),
  needsMonitor);

const modelScope = () => (scope === 'everything' ? 'all' : scope);
const focusedApp = () => state.windows.find(w => w.id === state.focused).app;

function paintKeys() {
  const from = state.windows.find(w => w.id === state.focused).at.screen;
  for (const b of actionBtns) b.querySelector('kbd').textContent = shortcutFor(modelScope(), b.dataset.action, from);
  scopeBtns[1].textContent = `All of ${focusedApp()}`;
}

function paintControls() {
  plugBtn.textContent = state.plugged ? 'Unplug the monitor' : 'Plug it back in';
  stage.classList.toggle('is-unplugged', !state.plugged);
  const other = actionBtns.find(b => b.dataset.action === 'other');
  other.disabled = !state.plugged;
  if (state.plugged) other.removeAttribute('aria-describedby'); else other.setAttribute('aria-describedby', 'needs-monitor');
  needsMonitor.hidden = state.plugged;
  for (const b of scopeBtns) b.setAttribute('aria-pressed', String(b.dataset.scope === scope));
  paintKeys();
}

// ---------- running steps ----------

function cancel() {
  timers.forEach(clearTimeout);
  timers = [];
  jumpToState();
}

const later = (ms, fn) => { timers.push(setTimeout(fn, ms)); };

// Animates `steps` one after another; resolves when the last move has landed.
function run(steps) {
  const instant = reduced.matches;
  if (instant) {
    stage.classList.add('instant');
    for (const s of steps) for (const m of s.moves) place(m.id, m.to);
    void stage.offsetWidth;
    stage.classList.remove('instant');
    caption.textContent = steps.map(s => s.caption).join(' ');
    settle = Promise.resolve();
    return settle;
  }
  settle = new Promise(resolve => {
    let t = 0;
    steps.forEach((s, i) => {
      if (i > 0) t += BETWEEN_STEPS_MS;
      later(t, () => { caption.textContent = s.caption; });
      s.moves.forEach((m, j) => {
        const e = winEls.get(m.id);
        later(t + j * STAGGER_MS, () => { place(m.id, m.to); });
        if (s.who === 'shepherd') {
          later(t + j * STAGGER_MS + MOVE_MS, () => e.classList.add('ring'));
          later(t + j * STAGGER_MS + MOVE_MS + RING_MS, () => { e.classList.remove('ring'); e.classList.add('landed'); });
        }
      });
      t += Math.max(0, s.moves.length - 1) * STAGGER_MS + MOVE_MS + (s.who === 'shepherd' ? RING_MS : 0);
    });
    later(t + 30, resolve);
  });
  return settle;
}

function doPlug() {
  cancel();
  const steps = state.plugged ? unplug(state) : plugIn(state);
  paintControls();
  return run(steps);
}

function visitor() {
  if (!visitorClicked) { visitorClicked = true; cancel(); }
}

plugBtn.addEventListener('click', () => { visitor(); doPlug(); });

for (const b of scopeBtns) b.addEventListener('click', () => {
  visitor();
  scope = b.dataset.scope;
  paintControls();
});

for (const b of actionBtns) b.addEventListener('click', () => {
  visitor();
  cancel();
  const r = act(state, modelScope(), b.dataset.action);
  if (r.error) { caption.textContent = r.error; return; }
  r.steps[0].caption += ` (${r.keys})`;
  paintControls();
  run(r.steps);
});

// ---------- start ----------

jumpToState();
paintFocus();
paintControls();
caption.textContent = 'This is a laptop and an external monitor. Try unplugging it.';

if (!reduced.matches) {
  later(AUTOPLAY_MS, () => {
    if (visitorClicked) return;
    doPlug().then(() => later(1200, () => { if (!visitorClicked) doPlug(); }));
  });
}

window.__demo = { state, get settled() { return settle; } };

// The replug demo's state: six toy windows on a laptop (screen 1) and a monitor
// (screen 2), numbered as Window Shepherd numbers screens. Places are in 0–1 units
// of their screen. Every function leaves the state final at once, so a click that
// lands mid-animation always starts from where the last click ends; the view only
// animates the returned steps.

const FULL = { x: 0, y: 0, w: 1, h: 1 };
const NINETY = { x: .05, y: .05, w: .9, h: .9 };
const MACOS_PUTS_BACK = ['chrome-1', 'messages'];   // macOS puts a couple back on its own

const WINDOWS = [
  ['notes', 'Notes', 'Notes', { screen: 1, x: .06, y: .08, w: .6, h: .7 }],
  ['chrome-1', 'Chrome', 'Chrome', { screen: 2, x: .05, y: .08, w: .55, h: .75 }],
  ['chrome-2', 'Chrome', 'Chrome', { screen: 2, x: .40, y: .15, w: .55, h: .75 }],
  ['code-1', 'VS Code', 'VS Code', { screen: 2, x: .10, y: .20, w: .50, h: .70 }],
  ['code-2', 'VS Code', 'VS Code', { screen: 1, x: .30, y: .20, w: .65, h: .70 }],
  ['messages', 'Messages', 'Messages', { screen: 2, x: .62, y: .50, w: .33, h: .42 }],
];

export function createDemo() {
  return {
    plugged: true,
    focused: 'chrome-1',
    windows: WINDOWS.map(([id, app, label, home]) => ({ id, app, label, home: { ...home }, at: { ...home } })),
    remembered: null,   // the monitor setup's arrangement, kept at unplug
  };
}

export function focus(s, id) {
  if (s.windows.some(w => w.id === id)) s.focused = id;
}

function move(s, w, to) {
  w.at = { ...to };
  return { id: w.id, to: { ...to } };
}

const sameAt = (a, b) => ['screen', 'x', 'y', 'w', 'h'].every(k => a[k] === b[k]);

export function unplug(s) {
  if (!s.plugged) return [];
  s.remembered = Object.fromEntries(s.windows.map(w => [w.id, { ...w.at }]));
  s.plugged = false;
  const moves = s.windows.filter(w => w.at.screen === 2).map((w, i) => {
    const x = .04 + i * .05, y = .06 + i * .05;
    return move(s, w, { screen: 1, x, y, w: Math.min(w.at.w, 1 - x), h: Math.min(w.at.h, 1 - y) });
  });
  return [{ who: 'macos', moves, caption: 'You unplugged. macOS piles everything onto the laptop.' }];
}

export function plugIn(s) {
  if (s.plugged) return [];
  s.plugged = true;
  const back = s.remembered ?? Object.fromEntries(s.windows.map(w => [w.id, w.home]));
  const away = s.windows.filter(w => back[w.id] && !sameAt(w.at, back[w.id]));
  const byMac = away.filter(w => MACOS_PUTS_BACK.includes(w.id) && back[w.id].screen === 2);
  const rest = away.filter(w => !byMac.includes(w));
  return [
    { who: 'macos', moves: byMac.map(w => move(s, w, back[w.id])), caption: 'Plugged back in. macOS puts a couple back on its own…' },
    { who: 'shepherd', moves: rest.map(w => move(s, w, back[w.id])), caption: '…and Window Shepherd puts back the rest, exactly where they were.' },
  ];
}

const KEY = { full: 'F', ninety: 'G', center: 'C' };

export function shortcutFor(scope, action, fromScreen) {
  const other = fromScreen === 2 ? '1' : '2';
  if (scope === 'all') return action === 'other' ? `⌃⌥⌘${other}⇧` : 'menu: Everything';
  const mods = scope === 'app' ? '⌃⌥⌘' : '⌥⌘';
  return mods + (action === 'other' ? other : KEY[action]);
}

const WHAT = { full: 'Full screen', ninety: '90%', center: 'Centered', other: 'the other screen' };

export function act(s, scope, action) {
  const focused = s.windows.find(w => w.id === s.focused);
  const keys = shortcutFor(scope, action, focused.at.screen);
  if (action === 'other' && !s.plugged) {
    return { steps: [], keys, error: "There's only the laptop right now. Plug the monitor back in first." };
  }
  const targets = scope === 'window' ? [focused]
    : scope === 'app' ? s.windows.filter(w => w.app === focused.app)
    : s.windows;
  // ⌥⌘n / ⌃⌥⌘n / ⌃⌥⌘n⇧ send every target to screen n: the one opposite the focused window,
  // full screen on the laptop and 90% on the monitor (content.md 5.3).
  const dest = focused.at.screen === 1 ? { screen: 2, ...NINETY } : { screen: 1, ...FULL };
  const moves = targets.map(w => {
    const { screen } = w.at;
    if (action === 'full') return move(s, w, { screen, ...FULL });
    if (action === 'ninety') return move(s, w, { screen, ...NINETY });
    if (action === 'center') return move(s, w, { screen, x: (1 - w.at.w) / 2, y: (1 - w.at.h) / 2, w: w.at.w, h: w.at.h });
    return move(s, w, dest);
  });
  const who = scope === 'window' ? 'This window' : scope === 'app' ? `${focused.app}'s windows` : 'Everything';
  return { steps: [{ who: 'you', moves, caption: `${who} → ${WHAT[action]}` }], keys };
}

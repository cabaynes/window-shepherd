# windowshepherd.com — content source of truth

This is the single place for what the Window Shepherd website says: the story, the pitch, every fact and claim, the comparison with Rectangle, and the structure of the page. Every fact on the page must appear here first. Every **[verify at release]** item must be rechecked on the shipped build before launch.

- **Status:** draft 2.2, 2026-10-24 (draft 2 was 2026-10-23). Draft 1 was reviewed by five readers: a long-time Rectangle user, a non-technical office worker, a product manager who works at two desks, a fact-checker working from the code, and a landing-page writer. What changed because of them is in section 12. The app isn't downloadable yet: signing waits on Apple Developer enrollment.
- **The site:** one page at windowshepherd.com (domain at Squarespace). How it's built and hosted is decided later.
- **Voice:** first person, Charles, soft and plain. See section 8.
- **Marking:**
  - **[Charles?]** marks a choice only Charles can make. They're all collected in section 11.
  - **[verify at release]** marks something true of the code but not yet tested on a real setup.

---

## 1. The pitch

### Headline and subhead (hero)

> **Quickly tidy your app windows, move them between screens, and put it all back the way it was.**
>
> A free Mac app I built, mostly for myself. Quickly resize or maximize a single window, an entire app, or everything open, at once. It also remembers where every window was for each different multi-screen setup you use, puts them back when you plug in again, and can easily move windows between those screens with a single click.

Under the button: **Free · Open source · macOS 14 or later**

Right under the hero, for the people who will never touch a shortcut (the non-technical reviewer's most important point):

> You don't have to learn any shortcuts. Once it's running, it puts your windows back by itself when you plug your external monitor in. If you'd like to move windows yourself, there's a small menu at the top of your screen, and keyboard shortcuts too if you like them.

And one line for the Rectangle users who'll arrive asking "how is this different?" (point 1 below), linking down to section 6 of the page:

> If you use Rectangle, think of this as a supplement: it does the things I wished Rectangle did, and you can use both.

### The three points the page must make clear (Charles, 2026-10-24)

Each one shows up in the hero or right below it, in the story, and in its own section. Charles's own words:

1. **A supplement to Rectangle.** "It does things I wish Rectangle did, and skips the parts of Rectangle that I didn't personally use." It's not a replacement and not a rival.
2. **Lots of windows from the same app.** "I always have multiple windows of Chrome, or VS Code, open at once, and I needed a quick way to organize and move them." That means resize, maximize, center or move one window, all of an app's windows, or everything.
3. **Several different monitor setups.** "Moving across multiple different multi-monitor setups would force me to manually move them around to my preferred location, often when Mac would fail to remember this." Window Shepherd remembers each setup and puts every window back.

### Headline

Chosen by Charles (2026-10-24) and now in the hero above: **"Quickly tidy your app windows, move them between screens, and put it all back the way it was."** It covers points 2 and 3. The earlier candidates can serve as section headers:

- Your windows, back where they were.
- Unplug, replug, and everything's back where it was.
- For people with lots of windows and more than one screen.

### What the page is built on (two moments, and one idea that ties them together)

1. **The replug.** Sit down at either desk, plug in, and your windows go back to how you left them there. There's nothing to save.
2. **One window, a whole app, or everything.** Every action works at three sizes of "who":
   - **Tidy up where they are.** Maximize, 90%, 60%, center, a half or a corner, for this window, every window of an app, or everything at once. Each window is resized on the screen it's already on. (Charles, 2026-10-24: this was missing from draft 2.)
   - **Send them somewhere.** Move this window, every window of an app, or everything to another screen.
3. The idea that ties them together: **more keys, more windows.** One key acts on this window, add ⌃ for every window of the app, add ⇧ to do it on the next screen. "Everything" is one click in the menu, or ⌃⌥⌘ + a screen number to send it all to that screen.

Single-window snapping on its own is something Rectangle already does well. What's different here is doing the same thing to many windows at once, so that's how the page presents it.

### The honest version of the replug pitch (important)

macOS 14 and later already puts **some** windows back on its own when you reconnect a monitor. In Charles's live test on 2026-10-23, macOS moved most windows back by itself and Window Shepherd fixed the rest (2 of about 41). So the page must not say "macOS puts nothing back". What Window Shepherd adds:

- **All of them, exactly.** Every window goes back to its exact spot and size, including the ones macOS misses or leaves in the wrong place.
- **Both directions.** When you unplug, your laptop-only arrangement comes back too, rather than everything piled up in one spot.
- **Each desk separately.** Home monitor and office monitor each get their own arrangement.
- **It waits for slow apps.** It tries again at 10 and 20 seconds for apps that are slow to wake up.

Suggested line for the page:

> macOS puts a few windows back on its own, but for me it was always hit and miss. Window Shepherd makes sure every window goes back to exactly where it was.

---

## 2. Who it's for

Write to these people; don't name them as personas on the page.

- **The two-desks person.** Home desk with one monitor, office desk with a different one. This is the strongest case and should lead Moment 1.
- **The laptop-plus-monitor person.** Unplugs for meetings, plugs back in, rearranges by hand every time. Often not a keyboard person at all.
- **The many-windows person.** Six Chrome windows, three VS Code windows, Slack, Figma. Moving "all of Chrome" to the big screen, or making all of them the same size again after they drift, is the daily chore.
- **The Rectangle person.** Knows ⌥⌘←, wants the replug and the whole-app moves on top.

Who it's probably **not** for. Say this kindly, in the FAQ:

- Fine-grained tiling (thirds, sixths, ninths), drag-to-snap, ultrawide layouts: Rectangle is where those features live.
- Named layouts you switch between, or layouts that launch apps: Rectangle Pro, Moom and Stay do that.
- Restoring windows after a restart.

---

## 3. Page framework (section order)

Agreed direction from the reviews: show the proof before the person, and keep the page short. The README holds the detail.

1. **Hero:** headline, subhead, the "no shortcuts needed" line, the supplement-to-Rectangle line, the replug clip (must-have, see 10), and the button.
2. **The replug (two desks):** 3–4 short lines plus the honest macOS line.
3. **One window, a whole app, or everything:** tidy up in place (maximize, 90%, center, halves) and send to another screen, for one window, all of an app's windows, or everything. The four-step "more keys, more windows" ladder, and a mouse-first menu screenshot.
4. **The story:** Charles's intro, about 90 words, with an optional photo.
5. **How to start, in 3 steps:** install, allow Accessibility (with the reassurance text), then just work.
6. **Using it with Rectangle:** prose, not a table (section 4.5).
7. **Trust:** "Built not to slow your Mac down" and privacy together, in five lines.
8. **FAQ:** section 7.
9. **Footer:** GitHub, changelog (GitHub Releases) with the current version and date, PRIVACY.md, MIT license, credits, "Made by Charles Baynes", buy me a coffee.

### Before the download exists

> **Coming soon.** I'm waiting on Apple to sign the app. The code is on GitHub now, and you can watch the repo to hear when it's out.

The button says "Watch for the release on GitHub". Don't set up an email list: it needs a provider and a privacy policy, and it would weaken "collects nothing". Don't promote the page widely until the download is live.

---

## 4. Page copy, section by section (draft wording)

### 4.1 The replug

> **Sit down, plug in, and everything's back.**
>
> I move between a few different monitor setups, and my Mac would often forget where my windows went, so I'd end up moving them back to my preferred spots by hand. Window Shepherd keeps a separate arrangement for each setup, and for the laptop on its own. When I plug in, my windows go back to how I left them on that setup, and when I unplug, the laptop goes back to how I had it.
>
> - There's nothing to set up or save. It keeps track as you go.
> - If you move a window while it's putting things back, it leaves that one alone.
> - It keeps trying for about 20 seconds, because some apps are slow to wake up.
> - Even two identical monitors are kept apart. **[verify at release]**
>
> macOS puts a few windows back on its own, but for me it was always hit and miss. Window Shepherd makes sure every window goes back to exactly where it was.
>
> The first time you connect a new monitor, there's nothing to remember yet, so you arrange things once. After that, it remembers.

### 4.2 One window, a whole app, or everything

> **Resize, maximize, center or move: one window, every window of an app, or everything.**
>
> I always have several Chrome windows and a few VS Code windows open at once, and I needed a quick way to organize and move them. Now I can make every Chrome window the same 90%, center them all, or maximize everything in one go, each on the screen it's already on. And when I want them on another screen, it's the same idea: one window, a whole app, or everything.
>
> ⌥⌘G puts this window at 90%.
> Add ⌃ to do it for every window of the app: ⌃⌥⌘G.
> Add ⇧ to do it on the next screen: ⌥⌘G⇧.
> And ⌃⌥⌘2 sends every window of the app to screen 2, while ⌃⌥⌘2⇧ sends everything.
>
> Prefer the mouse? Click the icon at the top of your screen, pick a size (full screen, 90%, 60%, center, a half or a corner), then pick this window, all of an app's windows, everything, or any other open app by name.

The sizes are full screen, 90%, 60%, centered at the same size, the four halves and the four corners. Show one example of each "who" on the page, rather than the full grid of sizes times scopes.

Teach the symbols once, near the first one: "⌃ is Control, ⌥ is Option, ⌘ is Command, ⇧ is Shift."

Screenshot: the menu, opened with the mouse, with the 90% submenu showing "This window / All Chrome windows / Everything".

Optional, a short expandable "All the shortcuts" list (section 5.4), or a link to the README for it.

### 4.3 The story (about 120 words) **[Charles?]**

> Hi, I'm Charles. I've used Rectangle for years and I love it. But I always have several windows of the same app open, like Chrome or VS Code, and I needed a quick way to organize and move them together. I also move between a few different monitor setups, and my Mac would often forget where everything went, so I'd move it all back by hand. So I built something for myself, first as a small script and now as a proper Mac app. I think of it as a supplement to Rectangle: it does the things I wished Rectangle did, and skips the parts I didn't personally use. I thought it might help someone else too.

Optional lines, each a separate choice for Charles:

- "I'm not a developer by trade; I built this with the help of AI (Claude Code)." The structure reviewer recommends keeping this as one sentence, because it's honest and suits a portfolio piece.
- "I've used it every day since [month]." This stands in for social proof: a date, not hype.
- A photo.
- A link to cccccccharles.github.io or LinkedIn.

Never mention: employers, job status, other businesses, personal life.

### 4.4 How to start

> 1. Download it and drag it to Applications.
> 2. Open it. Your Mac will ask you to allow Window Shepherd in Accessibility. That sounds bigger than it is. It's the same permission every window app needs, and it only lets Window Shepherd move and resize windows. It can't see what's inside them, and it doesn't send anything off your Mac. The app shows you exactly where to click, and you can turn it off any time in System Settings.
> 3. That's it. Just work as usual. It starts with your Mac, and there's nothing to set up.

Next to the download button, once released: "Signed and checked by Apple" (the plain way to say notarized).

### 4.5 Using it with Rectangle (prose, not a table)

> **A supplement to Rectangle, not a replacement.** I'm a big fan of Rectangle. Window Shepherd does the things I wished Rectangle did (moving and tidying all of an app's windows at once, and remembering each monitor setup), and it skips the parts of Rectangle I didn't personally use.
>
> If you mostly move one window at a time, Rectangle is probably all you need. It's where to go for fine-grained tiling (thirds, sixths, ninths), drag-to-snap and tiling a whole screen at once, and it's a mature app a great many people rely on.
>
> Window Shepherd might help if you keep several windows per app, move between different monitor setups, and are tired of putting everything back by hand. **You can use both.**
>
> The two share only a couple of shortcuts. While Rectangle is running, Window Shepherd steps aside on those, tells you once which ones, and takes them back when Rectangle quits.
>
> If you already have Rectangle Pro, its saved layouts cover a lot of this. Window Shepherd is for people who'd rather not save or keep layouts up to date.

Credit line in the footer: "The halves, full screen and center keys follow the Spectacle-style keys many Rectangle users already know. Thank you to Rectangle and Spectacle."

### 4.6 Trust

> **Built not to slow your Mac down.** The very first version of my script froze my whole laptop when one app stopped responding, so everything since has been built around not letting that happen. It never waits more than half a second on an app, a frozen app gets skipped and named rather than holding anything up, and its only background work is a light check every 2 seconds that reads the window list macOS already keeps.
>
> **Private.** It doesn't send anything about you anywhere. Its only connection is checking for updates. It asks for one permission, to move windows, and it can't see what's inside them.
>
> **Free and open.** No trial, no account. Anyone can read how it's made on GitHub.

Measure before claiming any CPU or battery figure: idle CPU in Activity Monitor over a few minutes. **[verify at release]** If it's tiny, add it: "On my MacBook it uses about X% CPU when idle."

---

## 5. Facts reference (what's true, with the corrections from the fact-check)

Checked against `main` at 9191ace and the parity checklist (all 37 lines live-tested 2026-10-23), then by a fact-check of about 45 claims against the code.

### 5.1 Auto-restore

- Remembers each window's spot per **screen setup** (laptop only, laptop + monitor A, laptop + monitor B, monitor only with the lid closed). It works in both directions: plugging in and unplugging.
- Screens are identified by `CGDisplayCreateUUIDFromDisplayID`. Identical monitors that report no serial number can share an ID. **[verify at release]** with two identical monitors before saying "even two identical monitors are kept apart".
- Restore passes run at **3, 10 and 20 s** after a setup change (`Shepherd.swift:316`).
- A spot is recorded once it has been seen twice, about **2 s** apart (`LayoutBook.swift:61-63`), so the mid-unplug shuffle isn't saved.
- If you move a window yourself during the passes, it isn't put back.
- Windows minimized, hidden or on another Space are kept **30 days**, then forgotten (`LayoutBook.swift:28`).
- Survives quitting and reopening Window Shepherd (tested live).
- **Limits:**
  - Windows of an app that was quit or relaunched, and windows after a restart, are new to macOS, so they aren't restored. Workaround to put in the FAQ: ⌃⌥⌘2 sends all of an app's windows to the big screen in one go.
  - **First visit to a new monitor:** nothing to restore yet.
  - **Sleep, wake and the lid:** there's no special handling. The 2 s check notices the new setup after wake, so it should work. **[verify at release]**
  - **Three or more displays, native full-screen windows, Stage Manager, Sidecar/AirPlay, docks and hubs:** untested. **[verify at release]**

### 5.2 Moves

- **Every size works on three scopes**: full screen, 90%, 60%, center (same size), the four halves and the four corners. The scopes are this window, every window of an app, and everything. Sizes act on the screen each window is already on. "Move to <screen>" and the ⇧ / number keys change screens.
  - **Keyboard:** this window (⌥⌘ + key) and every window of the front app (add ⌃; not the corners, which already use ⌃).
  - **Menu:** this window, all of the front app's windows, **everything**, or **any other open app by name**, without switching to it first. Resizing everything in place has no keyboard shortcut; it's one click in the menu (`MenuModel.swift:132-146`).
  - **Everything to one screen:** ⌃⌥⌘ + screen number + ⇧, or "Move to" in the menu.
- Moves act on normal windows that are on screen now. Windows on other Spaces aren't moved.
- Floating panels and toolbars are never moved (for example Zoom's meeting controls). A regular Zoom meeting window is moved like any other window.
- **Whole-app moves** bring that app to the front. **"Everything" moves** don't change the front app (`Shepherd.swift:114-116`).
- **Messages:**
  - **Single-window keyboard moves** are silent unless something goes wrong.
  - **Menu moves** and **bulk moves** show "Moved N windows → …" (`Shepherd.swift:208`).
- **A frozen or busy app:**
  - Every question to an app gives up after **0.5 s** (`LiveWindowSystem.swift:10`).
  - If one window takes over **1.5 s**, the app can't list its windows, or it refuses a move, it's tried again with growing waits (2 s, 4 s, 8 s…, up to 16 s apart) for up to **60 s** after a screen change, or **30 s** for a move you asked for (`RestoreTiming.patience`, `MoveTiming.movePatience`). If it still fails, it's skipped and named in the message.
  - Until your next move or screen change, the menu offers "Retry N windows that didn't move" (`RetryOffer.swift`).
  - After a restore that left windows behind, the ⧉ flashes until you open the menu, and, while some windows are out of place, the menu's top row offers **Put back N windows as they were at <time>**, from the frozen copy taken when the screens last changed (`Shepherd+Revert.swift`).
  - Windows opened while undocked go to the biggest screen at 90% when you plug in, by default (`UndockedWindows.swift`).
- It can't pick out *some* of an app's windows (one Chrome project): it moves all of an app's windows, or one window.

### 5.3 Screens and numbers

- Screens are numbered **1 = the laptop**, then monitors **left to right**.
  - Lid closed, or a desktop Mac: screen 1 is the leftmost monitor (`Screens.swift:55-61`).
  - Number keys stop at **9**.
- The number keys go **full screen on the laptop and 90% on monitors**. This is deliberate: a monitor gets a little margin so the desktop shows round the edge.
- Number keys exist only for connected screens, and **only with 2 or more screens**. With one screen there are none, so apps keep those keys.
- "Move to" rows in the menu are one per size, for example "Move to DELL U2718Q (2) — 90%". They only list screens the window isn't already on. Clicking the row moves this window; its submenu offers the whole app or everything.

### 5.4 Shortcuts (defaults)

Keyboard order: ⌃ ⌥ ⌘ key ⇧. ⌃ = Control, ⌥ = Option, ⌘ = Command, ⇧ = Shift.

| Keys | Does |
|---|---|
| ⌥⌘ ← → ↑ ↓ | this window: left / right / top / bottom half |
| ⌥⌘F · ⌥⌘G · ⌥⌘H · ⌥⌘C | full screen · 90% · 60% · center |
| ⌃⌘ ↑ → ← ↓ | corners: top left · top right · bottom left · bottom right |
| add ⌃ | every window of the app (not the corners, which already use ⌃; use the menu for those) |
| add ⇧ | on the next screen |
| add ⌃ and ⇧ | every window of the app, on the next screen |
| ⌥⌘1 · ⌥⌘2 … | this window → screen n |
| ⌃⌥⌘1 · ⌃⌥⌘2 … | every window of the app → screen n |
| ⌃⌥⌘1⇧ · ⌃⌥⌘2⇧ … | everything → screen n |
| ⌃⌥⌘M | the menu, under the mouse |

- Every main shortcut can be changed (⧉ → Customize shortcuts…).
- The extra keys (⌃ for the whole app, ⇧ for the next screen) and the screen keys (⌥⌘ + number) are fixed and explained in that window.
- Rectangle overlap:
  - The halves, ⌥⌘F and ⌥⌘C match Rectangle's **Spectacle-style** set; the corners and ⌥⌘G / ⌥⌘H don't.
  - Shared keys while Rectangle runs: **2** with its Recommended set (⌃⌥⌘← ⌃⌥⌘→), **12** with its Spectacle set.

### 5.5 The menu

- A menu bar icon: a shepherd's crook hooking a stack of windows. It turns **red while a move or restore is running**, so you can see it's working.
- **Action first, then who:** pick a size, half or corner, then choose This window, All [app] windows, Everything, or any open app by name.
- Shortcuts appear beside every row, and a "Keyboard shortcuts" submenu lists them all.
- ⌃⌥⌘M opens it under the mouse.

### 5.6 Shortcut clash warnings (FAQ and README, not the page)

- **macOS shortcuts:** blocked in red.
- **App menus and the built-in list:** the menus of open apps plus a built-in list of **429** shortcuts. That list covers popular apps and macOS text editing; there are also 47 macOS system shortcut names. Shown in amber: Window Shepherd wins, and it asks before saving.
- **Background shortcuts:** Google Drive's search key (advice: change Drive's to ⌥⌘D⇧) and, while Rectangle runs, Rectangle's keys (purple).

### 5.7 Performance (the precise version)

- The menu and the window memory read macOS's window list. They never talk to apps.
- Apps are asked things, through Accessibility, only during moves and restores, and while Customize Shortcuts is open (it reads open apps' menus for the clash check, time-boxed to 0.4 s per app and 3 s overall).
- **Every 2 seconds**, one light check:
  - It reads the window list to record positions.
  - It notices screen changes, as a backstop to macOS's own notification.
  - It checks whether Rectangle is running.
  - It updates the number keys.
- A 1 s permission check runs only while the first-run window is open.
- Each app gets its own lane, so a frozen app delays only itself.

### 5.8 Privacy (match PRIVACY.md exactly)

- **Network:** only the update check (Sparkle, an update feed on GitHub). No analytics, telemetry or crash reports, and no account.
- **Accessibility:** used to move and resize windows, and to read open apps' menus for the clash check while Customize Shortcuts is open. It never reads what's inside your windows.
- **Other settings it reads, to warn about clashes, keeping nothing:**
  - macOS's shortcut settings and your custom app shortcuts.
  - Google Drive's search key.
  - Rectangle's keys, every 2 s, only while Rectangle runs.
- **What it stores, on your Mac only:**
  - your shortcuts
  - where your windows were (window number, app name, position; forgotten after 30 days unseen)
  - a small log (under 512 KB)

### 5.9 Requirements and install

- **macOS 14 Sonoma or later** (`project.yml`).
- **Apple Silicon only, today.** The current Release build is arm64-only (checked with `lipo`). Either set `ARCHS` for a universal build before release, or say "Apple Silicon Macs". **[verify at release]** **[Charles?]**
- Accessibility onboarding notices the permission by itself. Launch at Login is on by default and can be switched off in the menu.
- Updates: ⧉ → Check for Updates….
- Download: signed and notarized from GitHub Releases, plus `brew install --cask cabaynes/tap/window-shepherd`. Both are pending enrollment.
- Uninstall: quit it from the menu and drag it to the Trash. To remove everything, also delete `~/Library/Application Support/Window Shepherd` and `~/Library/Logs/Window Shepherd`.

### 5.10 How it's made (footer line or FAQ only)

- Started as a Hammerspoon script used daily for weeks, then rebuilt as a native Swift app.
- **166 automated tests**, including a fake frozen app.
- A **37-point checklist** was checked on a real Mac before v1 was merged.

---

## 6. Rectangle and the other apps

### 6.1 Rectangle

Facts verified 2026-10-23 against Rectangle's README, site and release notes:

- Version 2.0.4 (2026-10-20), macOS 14+, free, MIT. Install from its site or with `brew install --cask rectangle`.
- Shortcuts:
  - halves, thirds, fourths, sixths, eighths, ninths and corners
  - almost maximize (90% by default, the counterpart of our ⌥⌘G)
  - maximize height, center, larger/smaller, restore, next/previous display
- Also:
  - drag-to-snap
  - repeated presses cycle through sizes
  - ignore apps, JSON import/export, Todo mode, screen-edge gaps
  - since 2.0, tile or cascade all the windows on a screen
- Not found in its docs: sending all of an app's windows, or everything, to another screen; restoring windows after a replug. These are unproven negatives, so the page says "Rectangle is built around one window at a time", never "Rectangle can't".

The page uses the prose in 4.5. The full feature table below is for the README or reference only:

| | Rectangle (free) | Window Shepherd (free) |
|---|---|---|
| Snap one window with the keyboard | Many positions incl. thirds to ninths | Halves, corners, full, 90%, 60%, center |
| Drag-to-snap, gaps, Todo mode | Yes | No |
| Tile or cascade a whole screen | Yes (2.0) | No |
| Window to another screen | Next/previous display | Next screen, or screen by number |
| Every window of an app, or everything, to another screen | Not in free Rectangle (Pro: app-level moves) | Yes, one shortcut or click |
| Put windows back after unplug/replug | Not in free Rectangle (Pro: saved layouts on connect) | Automatic, nothing to save |
| Price | Free (Pro $9.99 once) | Free |
| License | MIT | MIT |

### 6.2 The other apps that restore windows (one FAQ answer, with links)

Verified 2026-10-23 on each app's own site. Recheck within a week of launch.

- **Rectangle Pro:** $9.99 one-time, 3 Macs, 10-day trial, macOS 13.5+. Layouts apply on display connect or disconnect, on wake, or when a window opens, and can launch apps. App-level moves. iCloud sync. Don't claim window history: it isn't in the official docs.
- **Stay:** now free. v1.5.1, Aug 2025, macOS 14.6+. You store windows first; it keeps one set per display combination and restores automatically. No update in about 14 months.
- **Moom 4:** $15 (or an $8 upgrade). Saved layouts can apply automatically when the display setup matches, and on wake.
- **Display Maid:** $5.99 on the Mac App Store. Saved per display setup and restored automatically. Last updated October 2023.
- **Monitor Glue:** free, MIT, macOS 14+. Remembers automatically per monitor and restores on reconnect, lid open, wake or unlock. Very new and small.

FAQ wording:

> Yes, a few. Rectangle Pro, Moom, Stay and Display Maid restore layouts you save first, and Monitor Glue remembers automatically like Window Shepherd does. Window Shepherd puts automatic memory together with moving whole apps or everything, and it's free.

Never claim to be the only one.

---

## 7. FAQ (draft answers, two or three sentences each)

1. **Is it really free?** Yes. No trial, no subscription, no account. If it saves you time, there's a "buy me a coffee" link, and that's all.
2. **Do I need to learn the shortcuts?** No. The restore is automatic, and everything else is in the menu at the top of your screen. The shortcuts are there if you like them.
3. **Do I have to save layouts?** No. It keeps track as you go, separately for each screen setup.
4. **What happens the first time I plug into a new monitor?** There's nothing to remember yet, so you arrange things once. After that, it puts them back every time.
5. **Does it work when I close the lid, or after sleep?** **[verify at release]** Draft answer if it holds: "Yes. When the screens change, including after sleep or with the lid closed at your desk, it puts your windows back for that setup."
6. **Does it restore windows after a restart, or after an app restarts?** Not yet. It puts back windows that stayed open; a window reopened after a restart is new to macOS. When Chrome restarts for an update, I press ⌃⌥⌘2 to send all its windows to the big screen in one go.
7. **Do I have to uninstall Rectangle?** No. They work side by side, sharing only a couple of shortcuts, and Window Shepherd steps aside on those while Rectangle runs.
8. **Why does it need Accessibility permission?** Use the "How to start" reassurance text (4.4).
9. **Will it slow my Mac down?** I built it so a frozen app can't hold it up, and its only background work is a light check every 2 seconds. (Add the idle CPU figure once measured.)
10. **Can I move just some of my Chrome windows?** Not as a group. It moves one window, or every window of an app. Move the others one at a time with a shortcut.
11. **What about other desktops (Spaces), full screen apps, Stage Manager or Zoom?** Moves work on the windows you can see. Windows on other desktops are left where they are, and Zoom's floating controls are never moved. Full-screen apps and Stage Manager haven't been tested yet. **[verify at release]**
12. **Does it work with two identical monitors, docks or three monitors?** **[verify at release]** for each before answering yes. The honest answer today: "Screens are numbered 1 for the laptop, then left to right. I've only tested it with one monitor so far."
13. **Does it work on an ultrawide?** Yes, though halves on an ultrawide are big and there are no thirds. Rectangle is better for that.
14. **Which Macs does it run on?** macOS 14 Sonoma or later. Apple Silicon only, or also Intel, depends on the release build. **[Charles?]** **[verify at release]**
15. **Is my data collected?** No. Nothing leaves your Mac except the update check. Link PRIVACY.md.
16. **Aren't there other apps that do this?** Use the 6.2 wording.
17. **How do I uninstall it?** Quit it from the menu and drag it to the Trash (see 5.9 for removing everything).
18. **How do I report a bug or suggest something?** GitHub Issues. **[Charles?]** Add an email address too?

---

## 8. Voice and claim rules

### Voice

- **First person, Charles, soft and plain.**
  - Hedge rather than boast: "I found myself", "it might help", "for me it was hit and miss".
  - No "the best", "seamless", "effortless", "blazing fast", and no "can't" about performance.
- Full spoken sentences with their small words, not billboard fragments.
- No exclamation marks in body copy.
- **Plain words on the page**, with the technical word only in the FAQ or README:

| Instead of | Say |
|---|---|
| the ⧉ menu / menu bar | a small icon at the top of your screen |
| Spaces | other desktops |
| notarized | checked by Apple |
| Sparkle | it checks for updates |
| MIT, open source | anyone can read how it's made (MIT in the footer) |
| hardware ID | even two identical monitors are kept apart (after it's verified) |
| telemetry | it doesn't send anything about you anywhere |

- Teach ⌃ ⌥ ⌘ ⇧ once in words. Shortcuts are always in keyboard order ⌃ ⌥ ⌘ key ⇧.
- Numbers instead of adjectives, but only where they help. Use "about 20 seconds" on the page, and leave 3/10/20 for the FAQ.
- The red icon means "so you can see it's working", not "keep your hands off". It never fights you.

### Claims we must never make

- That macOS puts nothing back on replug (it puts some back).
- That it restores windows after a restart or app relaunch.
- That it's the only app that restores windows automatically, or the only free one (Monitor Glue, and Stay is free).
- That Rectangle "can't" do something. Say it's built around one window at a time.
- That the single-window keys "match Rectangle's defaults". Only the halves, full and center match its Spectacle-style set.
- That it "can't" slow your Mac, or "never waits" on apps (it waits up to half a second).
- That only moves talk to apps (the clash check reads menus too).
- That it supports thirds, gaps, drag-to-snap, Stage Manager, three monitors, identical monitors, docks or sleep, until each is verified.
- That it runs on Intel Macs, until the build is universal.
- Window history for Rectangle Pro. Any user or download numbers. The Mac App Store.

---

## 9. Where each fact belongs

- **On the page:**
  - per screen setup, nothing to save, leaves your moves alone
  - "keeps trying for about 20 seconds"
  - resize, maximize, center or move: one window, a whole app, or everything, with one shortcut or click
  - the four-step ladder
  - a frozen app is skipped and named
  - collects nothing, one permission, free and open
  - the origin line about the frozen laptop
  - the honest macOS line
- **In the FAQ:**
  - the restart and relaunch limit (with the ⌃⌥⌘2 workaround)
  - the first visit to a new monitor
  - lid, sleep, Spaces, Stage Manager, Zoom, ultrawide, identical monitors, docks, three monitors
  - the 3/10/20 s timing, 30 days, changing shortcuts, the two shared Rectangle keys
  - other restore apps, uninstall, bug reports
- **README only:**
  - seen twice 2 s apart, 0.5 s / 1.5 s / 2 s / 4 s, per-app lanes
  - 429 shortcuts and the clash colours, 12 Spectacle keys
  - "action first, then who", the full shortcut table, the comparison table
  - tests and checklist (one footer line at most), competitor prices

---

## 10. Before launch

**Must-haves:**

1. **The replug clip.** It carries the whole page, and Charles has to record it, since Claude can't record the screen. Unedited, with a visible clock: unplug → windows pile onto the laptop → replug → windows slide back while hands stay off the keyboard. Caption: "Plug in. Wait a few seconds. That's it."
2. **Signed, notarized download.** Apple Developer enrollment comes first.
3. **Universal build, or say Apple Silicon only.** **[Charles?]**

**Verify on the release build, then update sections 5 and 7:**

- sleep and wake
- lid closed at the desk (clamshell)
- two identical monitors
- a dock or hub
- three monitors
- native full screen
- Stage Manager
- Sidecar or AirPlay
- idle CPU and memory

**Screenshots**, on a clean desktop with no personal window titles or file names:

- the menu opened with the mouse
- Customize Shortcuts (`docs/images/customize-shortcuts.png` exists, cropped to safe rows)
- the Accessibility step
- the app icon

**Also:**

- Recheck competitor facts (6.1, 6.2) within a week of launch.
- Fix the README's "Only an actual move talks to an app" (it should mention the clash check). **Done 2026-10-23.**

---

## 11. Decisions for Charles

Settled 2026-10-24: the headline (Charles's own), the "different monitor setups" wording (4.1), and the Chrome/VS Code line (4.2).

1. The story: approve the rewritten version (4.3). Decide on the optional lines: the AI line, "used it every day since…", photo, link.
2. Intel support: build universal, or say Apple Silicon only.
3. The bug-report channel: GitHub Issues only, or an email address too.
4. Whether to show the shortcut table on the page (expandable) or only link to the README.

---

## 12. Review log

### Draft 2.1 → 2.2 (Charles, 2026-10-24)

- Charles's three points are now explicit (1) and carried into the hero, story, 4.1, 4.2 and 4.5:
  - a supplement to Rectangle (it does what he wished Rectangle did, and skips what he didn't use)
  - many Chrome or VS Code windows that need organizing and moving together
  - several different monitor setups that macOS often failed to remember
- Charles's own headline is adopted. A small typo in his "who it's not for" line is fixed.

### Draft 2 → 2.1 (Charles, 2026-10-24)

- The hero subhead was reworded by Charles.
- Resizing, maximizing and centering in place, for one window, a whole app or everything, was missing as a headline claim. It's now part of the backbone (1), the section order (3), the copy (4.2), the facts (5.2) and the page list (9).

### Draft 1 → draft 2

- **Non-technical reader:**
  - The page never said shortcuts are optional, so the "no shortcuts needed" line now sits right under the hero.
  - Jargon is replaced on the page (8).
  - Accessibility gets reassurance text (4.4).
  - The lid and sleep question is added.
- **Rectangle user:**
  - The honest macOS line is added.
  - "Can't slow your Mac" is softened.
  - The Rectangle Pro question is answered in 4.5.
  - Identical monitors are marked verify.
  - Spaces, Stage Manager, Sidecar, three monitors and CPU are added to the FAQ and the verify list.
- **Two-desks product manager:**
  - Moment 1 now leads with two desks.
  - The first visit, the Chrome-relaunch workaround and "can't pick out some Chrome windows" are covered.
  - The ladder is taught in four lines, with the corners exception.
  - Ultrawide, docks and Zoom are in the FAQ.
  - The red icon is reworded.
- **Fact-checker** (about 45 claims, 12 fixed):
  - corners don't get whole-app keys
  - only keyboard moves are silent
  - number keys need 2+ screens and stop at 9; screen 1 when there's no laptop screen
  - only halves, full and center match Spectacle
  - the clash check also talks to apps
  - privacy now lists every read
  - the 2 s check does more than notice screens
  - "never waits" is overstated
  - **the build is arm64-only**
  - "Move to" rows are per size
  - identical monitors are unverified
  - the 429 list includes macOS text editing
- **Landing-page writer:**
  - Proof comes before the person.
  - Two moments plus the ladder.
  - The story is trimmed to about 90 words.
  - The comparison is prose (the table moved to reference).
  - The pre-release state is "Watch on GitHub" with no email list.
  - "How to start" in 3 steps, an uninstall FAQ, a changelog in the footer, credits.
  - Each fact is sorted into page, FAQ or README (9).
- **Competitor research:**
  - Rectangle 2.0 tiles and cascades whole screens.
  - Rectangle Pro has app-level moves and automatic layouts.
  - Stay is free now.
  - Monitor Glue is free and automatic.
  - Rectangle needs macOS 14+.
  - Rectangle Pro's window history is unverified.

## 13. Facts ledger

| Fact | Source |
|---|---|
| Restores at 3, 10, 20 s | `Shepherd.swift:316` |
| Seen twice, 2 s apart | `LayoutBook.swift:61-63` |
| 30 days | `LayoutBook.swift:28` |
| 0.5 s per question | `LiveWindowSystem.swift:10` |
| Retries with growing waits for 60 s (restore) / 30 s (move); 1.5 s window limit | `MoveStep.swift`, `Shepherd.swift` (`RestoreTiming.patience`) |
| Retry offer until the next move or screen change | `Shepherd.swift` (`apply`, `retryRows`) |
| Revert: frozen copy taken at unplug; kept if the setup was used under 60 s or windows were left behind | `LayoutBook.swift` (`setupChanged`) |
| Windows opened while undocked: on, biggest screen, 90% centered | `UndockedWindows.swift` |
| 429 app shortcuts + 47 system names | `known-shortcuts.json` |
| 2 / 12 shared keys with Rectangle Recommended / Spectacle | `BackgroundShortcuts.swift`, live log 2026-10-23 |
| Whole-app moves activate the app; everything doesn't | `Shepherd.swift:114-116` |
| Keyboard single-window moves are quiet | `Shepherd.swift:208` |
| Number keys need 2+ screens, up to 9 | `HotkeyBinder.swift:96-97`, `Bindings.swift:57` |
| Screen numbering, lid closed | `Screens.swift:55-61` |
| Clash scan limits 0.4 s per app / 3 s | `ClashScanner.swift:137-138` |
| Launch at Login on by default | `AppDelegate.swift:94` |
| macOS 14.0 | `App/project.yml:5,16` |
| arm64-only Release build | `lipo` on the Release app, 2026-10-23 |
| 166 tests, 0 failures | `swift test`, 2026-10-23 |
| 37/37 parity lines | `docs/parity-checklist.md` |
| macOS put most windows back itself in the replug test (Window Shepherd restored 2) | `~/Library/Logs/Window Shepherd/window-shepherd.log`, 2026-10-23 10:51 and 11:00 |

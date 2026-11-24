# windowshepherd.com — website design (2026-11-24)

## Intent
A fun, one-page site where strangers understand Window Shepherd in seconds and download it, and that Charles can point to from his portfolio (cccccccharles.com). The words come from `docs/website/content.md` (the source of truth for every claim, in Charles's soft, plain voice). The fun is in the look and in a **playable demo**, not in the copy.

## Decided by Charles
- **A playable demo** at the top of the page (chosen over a style-only page or a hidden mini-game).
- **Simple look, not the full cccccccharles palette:** white background; **Bungee Shade** (the cccccccharles display font) in **black** for the title and some headers; **blue `#003CFF`** as the highlight colour; **a dash of green `#00FF44`** here and there.

## Goals
- Someone with no interest in shortcuts gets it from the demo alone: unplug → windows pile up → plug in → they go back.
- Section order and copy per `content.md` section 3 (hero, the replug, one window / a whole app / everything, the story, how to start, using it with Rectangle, trust, FAQ, footer).
- Fast, accessible, readable on a phone; polished enough for a portfolio.

## Non-goals
- No email list, no analytics, no cookies ("collects nothing" must stay true).
- No second page, blog or docs site: the README holds the detail.
- No real screenshots with personal window titles or file names.

## Anti-goals (a failure even if it works)
- A demo that overclaims: macOS puts *some* windows back itself, and the demo must show that (content.md "The honest version").
- Any claim not in content.md, or a **[verify at release]** claim stated as fact.
- A generic template look, or a page that feels heavy or janky.

## Approaches considered
1. **Hand-written static page in this repo, served by GitHub Pages at windowshepherd.com** (chosen). One HTML file, one CSS, one JS, no build step; the demo is plain JS and CSS. Lives in `site/`, published by a GitHub Actions Pages workflow that uploads `site/` only. The Sparkle update feed (`appcast.xml`) lives there too at release.
2. A site framework (Astro, Next.js): a build step and dependencies for one page; nothing it adds is needed.
3. A separate website repo: splits the site from the app and its update feed for no gain.
Charles handed over the how; option 1 is Claude's call.

## The demo (hero)
- A line-drawn **laptop** and **external monitor** joined by a cable, with 5–6 toy windows labelled with app names (two Chrome, two VS Code, Notes, Messages), each with its own title-bar tint. No logos.
- **Unplug:** the cable comes out, the monitor goes dark, the windows slide onto the laptop and pile up.
- **Plug in:** the monitor wakes; after a beat macOS puts **a couple** back on its own (caption says so); then "Window Shepherd puts back the rest" and the rest glide to their exact spots, each briefly ringed in blue, with a small green tick as each one lands.
- A second set of controls shows "one window, a whole app, or everything": pick **This window / All of Chrome / Everything**, then **Maximize / 90% / Center / → other screen**; each press shows its real shortcut (from content.md 5.4).
- A live caption (`aria-live`) narrates each step. Buttons are real buttons, keyboard-usable. `prefers-reduced-motion` makes moves instant.
- Plays once by itself shortly after load (so people who never click still see the replug), then waits for clicks. *(Claude's call.)*
- Scales to phone width; controls stack under the scene.

## Look
- White page, black Bungee Shade for the wordmark and section headings; body text in the Mac system font (SF Pro on Macs; fast, native for a Mac app; *Claude's call*).
- Blue `#003CFF` for buttons, links, the demo's highlights and the active window; green `#00FF44` only as accents (the landing ticks, the "Free" badge), never for text on white (too faint to read).
- Self-hosted Bungee Shade (woff2 from cccccccharles, SIL Open Font License noted in the footer credits). No third-party requests.
- Favicon and app icon from the app's own icon (crook + windows). Open Graph card for link previews.

## Download button
Until the signed build exists: the "Coming soon" state from content.md 3 ("Watch for the release on GitHub"). One constant switches it to the DMG download at release.

## Hosting
- GitHub Pages via Actions from `site/`; custom domain windowshepherd.com (Squarespace DNS: Claude gives Charles the click path for the records).
- At release, the app's feed URL moves from `cabaynes.github.io/window-shepherd/appcast.xml` to `windowshepherd.com/appcast.xml` (nothing has shipped, so it's free to change); RELEASING.md part 4 updated to match.

## Later, not blocking
- The replug clip, when Charles records it, goes in "The replug" section; the demo stays in the hero.
- The "used it every day since [month]" month, the menu screenshot and the Accessibility-step screenshot (content.md 10).

## Left to the builder
Exact layout and spacing, animation timing, how the toy windows are drawn, and trims to the copy that keep its meaning and voice.

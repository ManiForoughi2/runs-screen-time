# Prompt for a new Claude chat — "Runs for the browser" (Chrome/Brave extension)

Copy everything below the line into a fresh Claude Code session in a new empty folder.

---

Build me a Chromium extension (Manifest V3, works identically in Chrome and Brave on macOS — I'll load it unpacked first, maybe Web Store later) called **Runs** — a desktop companion to my iOS screen-time app of the same name.

## The concept (must match the iOS app)

Distracting sites are "resting" by default. You get a limited number of timed **runs** per day (default: a shared pool of 4 runs, 3 minutes each; also support per-site runs/day as an alternative mode). To enter a blocked site you must **breathe first**: a full-screen overlay plays a slow breathing animation (inhale ~4s as a soft radial glow expands, exhale as it fades — this is the one place animation is allowed), and only after the breath completes can you click **START RUN**. The site is then usable for the run's minutes, a small countdown pill shows in the corner, and when time is up the block page returns. Out of runs → the block page says "out of runs for today. resets at midnight." and offers no way in. Midnight reset is local time.

## Blocked-site catalog

Ship this default catalog as toggle chips (user can also add custom domains). Subdomains count. instagram.com, tiktok.com, x.com, twitter.com, youtube.com, youtu.be, reddit.com, snapchat.com, facebook.com, threads.com, threads.net, pinterest.com, linkedin.com, twitch.tv, discord.com, tumblr.com, messenger.com, web.whatsapp.com, web.telegram.org, bereal.com, netflix.com.

## Technical requirements

- **MV3**, no remote code, no analytics, no network calls at all. Everything local.
- Interception: content script at `document_start` on catalog/custom domains renders the block/breathe overlay immediately (no flash of feed) + `declarativeNetRequest` as the hard layer where practical. Handle SPA navigation (History API) — YouTube/X never do full page loads.
- State in `chrome.storage.local`: catalog toggles, custom domains, mode (shared pool / per-site), minutes per run, runs per day, runs used today (keyed by yyyy-mm-dd so stale days auto-reset), active run {domain, endsAt}.
- `chrome.alarms` to end runs (content script also self-checks endsAt each second for the countdown pill — wall clock is the source of truth).
- A run for a domain frees ALL of that platform's domains (x.com + twitter.com together).
- Options page + toolbar popup: popup shows today's pool (filled/empty dots) and the active run countdown; options has the chips, mode, minutes/runs steppers, and a **commitment lock** (can't loosen settings until a chosen date; tightening always allowed).
- **Breathe duration setting**: off / 3s / 5s / 10s (default 5s). "Off" turns the breathe gate into a plain START RUN confirm.

## Design — strict, this is the brand

Minimalist to the bone, matching the iOS app: pure black background, pure white text, one monospace font (use a bundled open monospace like JetBrains Mono or IBM Plex Mono), lowercase body copy, UPPERCASE tracking-wide labels ("RUNS", "START RUN", "OUT OF RUNS FOR TODAY."), thin 1px hairline borders, rounded 12–16px corners, no icons except simple filled/empty circles for run pips, no gradients, no shadows, no color anywhere except white-on-black (the breathing glow is white at low opacity). The block page shows: wordmark "RUNS", the resting domain, remaining run pips, and the single primary button. Generous empty space. It should feel like a calm wall, not a nag screen.

## Deliverables

Complete working extension: manifest.json, service worker, content script + overlay css, popup, options page, a README with load-unpacked steps for Chrome and Brave, and a short manual test checklist (block appears pre-paint, breathe gate timing, run countdown, midnight reset, SPA navigation, multi-tab same-domain behavior — one run covers all tabs of that platform).

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Blue Balls of SPLORR!!** is a browser game: tap falling blue balls to keep them in the air; a new one arrives on a shrinking timer; one touching the floor ends the run. Odin compiled to `js_wasm32`. Started November 23, 2026. Rules and which of them are the user's decisions vs. provisional choices are in `DESIGN.md`; record any new rule there with the date. The title pun is deliberate; do not treat it, or the unwinnable design, as a problem.

## Layout

- `game/`: all rules and state (physics, drops, bops, scoring, a sound queue). No JS, no `core:os`. `game_test.odin` is `#+build !js`.
- `playtest/` (`#+build !js`, native only): scripted tappers over many runs, for tuning. Build with `odin build playtest -collection:bbs=. -o:speed -out:build/playtest`.
- `src/web/main.odin` (`#+build js`): drawing and input routing only. It imports `bbs:game` through `-collection:bbs=.`.
- `web/index.html`: the canvas shim (drawn balls, shadows and rings; m5x7 bitmap text; Web Audio blips in `SOUNDS`, ordered like `game.Sound`), the footer back links and the hidden LootLocker feedback link (no LootLocker game yet; the user's call). The canvas backing store is drawn at the whole-number zoom so circles are smooth.

## Build and run

```bash
tools/test.sh       # native tests and a wasm check of src/web
tools/build.sh      # build/web; --size for shipping
python3 -m http.server -d build/web 8053
```

`?demo` calls the `qa_demo` export (a fixed mid-run scene that never records a best). The browser pane throttles frames between tool calls.

## External resources

- **Vault:** `/home/yermom/git/bok-of-splorr/splorr` (read `Home.md` first for the standing rules, then `Tech/Odin wasm recipe.md`, `Tech/Release standard.md`, `Gotchas.md`). This game's note is `Games/Blue Balls of SPLORR!!.md`.

## Release and safety rules (from the vault's `Home.md`)

- Never `git push` or ship unless the user says so ("push" means `git push`; "ship" means itch.io).
- GitHub Pages: the repo is public (https://github.com/playdeezgames/blue-balls-of-splorr) and Pages serves `main` `/docs` at https://playdeezgames.github.io/blue-balls-of-splorr/ (since November 23, 2026). To update it, run `tools/pages.sh`, commit `docs/`, and push only when the user says push.
- itch.io material (`ITCH_DESCRIPTION.md`, cover, screenshots, `tools/ship.sh`, `shippit.sh`) is made only when the user decides the game goes to itch.io. On itch it is a "Metaphor", ships go through Coxswain, and anything an AI agent posts there says so.

# Blue Balls of SPLORR!! — design

*Keep them up. Don't let go.* A Metaphor about holding off a release. The title is a deliberate pun; the balls really are blue.

## The user's decisions (November 23, 2026)

- Literal blue balls; the loop is about holding off a release; the pun is the tagline, the copy is deadpan and euphemistic.
- Pitch "Don't Drop Them": keep the balls in the air. A new one joins every so often. Dropping one is game over. There is no win.
- Click or tap a ball to bop it upward (no paddle). Mouse and touch first.
- New balls arrive on a timer that slowly shortens. The score is the time held.
- Drawn shapes, no tileset or sprite sheet.
- Odin to `js_wasm32`, GitHub Pages first, itch.io decided later.

## Provisional (chosen while building the first playable; the user may change any of them)

- A bop sends the ball up at a fixed speed and sideways away from the point tapped, so aim matters. Taps within 5 px of a ball's edge still count; the nearest ball in reach is the one bopped.
- Balls bounce off the side walls, the ceiling (softly) and each other.
- A red marker blinks at the top for 1.2 s where the next ball will fall in.
- Gaps: 7 s from the first ball to the second, then each gap is 90% of the last, down to 2 s. At most 20 balls.
- Balls deepen from sky blue to navy as they fall low; a floor shadow grows under each.
- Result screen: "RELEASED.", the time held, a remark by duration ("That was quick.", "It happens to everyone.", "Respectable stamina.", "Impressive restraint.", "Okay, show-off."), and the longest run. Taps are ignored for 1 s after the drop.
- Keyboard (Enter, Space) and gamepad (A, Start) only start and restart; bopping is pointer only.
- Best time is kept in `localStorage` under `blue-balls-of-splorr:best` (tenths of a second).

## Tuning notes

`playtest/` taps the ball nearest to landing, with a reaction time and aim error. First playable (November 23, 2026), median survival over 200 runs: slow and sloppy 19 s, casual 23 s, focused 38 s, sharp 56 s (about 11 balls up at once).

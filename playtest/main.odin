// Native playtest: scripted tappers on the real rules, to tune the pacing.
// Build: odin build playtest -collection:bbs=. -o:speed -out:build/playtest
#+build !js
package main

import "bbs:game"
import "core:fmt"
import "core:slice"

Bot :: struct {
	name:  string,
	react: f32, // seconds between taps
	aim:   f32, // px of random error on each tap
	panic: f32, // taps only once a ball is below this y
}

BOTS := []Bot {
	{"slow and sloppy", 0.45, 7, 150},
	{"casual", 0.32, 5, 140},
	{"focused", 0.22, 3.5, 120},
	{"sharp", 0.15, 2.5, 100},
}

RUNS :: 200
CAP :: 600.0 // seconds; a run this long counts as endless

// Tap the ball that will reach the floor soonest (if it is low enough), on the side away from the
// nearer wall so it drifts back towards the middle.
play :: proc(b: Bot, seed: u64) -> (secs: f32, balls: int) {
	g := game.title(seed)
	game.new_game(&g)
	noise := game.Rng{seed ~ 0xABCDEF}
	wait: f32 = 0
	dt :: f32(1.0 / 60)
	for g.phase == .Playing && g.time < CAP {
		game.update(&g, dt)
		wait -= dt
		if wait > 0 {continue}
		pick := -1
		soonest := f32(1e9)
		for i in 0 ..< g.nballs {
			bl := g.balls[i]
			if bl.y < b.panic || bl.vy < 0 {continue}
			// time until the bottom reaches the floor: solve y + vy t + g t^2 / 2 = FLOOR_Y - RADIUS
			d := game.FLOOR_Y - game.RADIUS - bl.y
			v := bl.vy
			tt := (-v + sqrt(v * v + 2 * game.GRAVITY * d)) / game.GRAVITY
			if tt < soonest {pick, soonest = i, tt}
		}
		if pick < 0 {continue}
		bl := g.balls[pick]
		toward: f32 = bl.x < game.LOGICAL_W / 2 ? -1 : 1 // tap the outer side to push it inward
		ex := (game.unit(&noise) * 2 - 1) * b.aim
		ey := (game.unit(&noise) * 2 - 1) * b.aim
		game.click(&g, int(bl.x + toward * 4 + ex), int(bl.y + ey))
		wait = b.react
	}
	return g.time, g.nballs
}

sqrt :: proc(x: f32) -> f32 {
	if x <= 0 {return 0}
	r := x
	for _ in 0 ..< 20 {r = 0.5 * (r + x / r)}
	return r
}

main :: proc() {
	for b in BOTS {
		times := make([]f32, RUNS)
		defer delete(times)
		maxballs := 0
		for i in 0 ..< RUNS {
			s, n := play(b, u64(i + 1) * 7919)
			times[i] = s
			maxballs = max(maxballs, n)
		}
		slice.sort(times)
		fmt.printfln(
			"%-16s median %6.1fs  p10 %6.1fs  p90 %6.1fs  most balls %d",
			b.name,
			times[RUNS / 2],
			times[RUNS / 10],
			times[RUNS * 9 / 10],
			maxballs,
		)
	}
}

// Blue Balls of SPLORR!!: rules and state. No drawing and no JS; the web layer reads this and draws it.
//
// Blue balls fall under gravity. Click or tap one to bop it upward, away from the point you hit.
// A new ball drops in on a timer that shortens each time. When any ball touches the floor, the run
// is over. There is no win: the score is how long you kept them up.
// Design decisions are recorded in the vault: splorr/Games/Blue Balls of SPLORR!!.md.
package game

import "core:math"

LOGICAL_W :: 160
LOGICAL_H :: 240
FLOOR_Y :: 224 // the top of the floor; a ball whose bottom reaches it has dropped

// Tuning (provisional, first playable November 23, 2026).
RADIUS :: 9
REACH :: RADIUS + 5 // a click this close to a ball's centre still bops it
GRAVITY :: 260 // px/s^2
BOP_VY :: 235 // upward speed after a bop
BOP_VX :: 110 // sideways speed when hit on the very edge
KEEP_VX :: 0.3 // share of the old sideways speed a bop keeps
WALL_BOUNCE :: 0.85
CEIL_BOUNCE :: 0.5
BALL_BOUNCE :: 0.9
WARN_TIME :: 1.2 // seconds a drop marker shows before its ball appears
FIRST_GAP :: 7.0 // seconds from the first ball to the second
GAP_SCALE :: 0.9 // each gap is this much of the one before
MIN_GAP :: 2.0
MAX_BALLS :: 20
OVER_LOCK :: 1.0 // seconds after a drop before a tap restarts (frantic tapping must not skip the result)
STEP :: 1.0 / 240.0 // physics substep
MAX_DT :: 0.05

// Order must match SOUNDS in web/index.html.
Sound :: enum i32 {
	Bop,
	Warn,
	Arrive,
	Drop,
	Clack,
	Record,
}

// Keyboard and gamepad commands; the page maps keys and buttons to these.
Action :: enum i32 {
	Confirm,
}

Phase :: enum {
	Title,
	Playing,
	Over,
}

Rng :: struct {
	s: u64,
}

Ball :: struct {
	x, y:   f32,
	vx, vy: f32,
	squash: f32, // seconds left of the bop squash, for drawing
	hits:   int,
}

Game :: struct {
	phase:      Phase,
	rng:        Rng,
	balls:      [MAX_BALLS]Ball,
	nballs:     int,
	time:       f32, // seconds held this run
	gap:        f32, // the current gap between drops
	next_drop:  f32, // seconds until the next marker appears
	warn_t:     f32, // > 0 while a marker is showing
	warn_x:     f32,
	dropped:    int, // index of the ball that touched the floor
	over_t:     f32, // seconds since the drop
	bops:       int,
	best:       int, // tenths of a second
	new_best:   bool,
	save_best:  bool,
	ripple_x:   f32, // the last tap, for a little ring
	ripple_y:   f32,
	ripple_t:   f32,
	ripple_hit: bool,
	demo:       bool, // a QA scene: its run never counts as a best
	sounds:     [16]Sound,
	nsounds:    int,
}

// --- Randomness ---------------------------------------------------------------------------

// splitmix64: every random choice goes through this, so a seed replays exactly.
next :: proc(r: ^Rng) -> u64 {
	r.s += 0x9E3779B97F4A7C15
	z := r.s
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// A float in [0, 1).
unit :: proc(r: ^Rng) -> f32 {
	return f32(next(r) >> 40) / f32(1 << 24)
}

// --- Sounds -------------------------------------------------------------------------------

sound :: proc(g: ^Game, s: Sound) {
	if g.nsounds < len(g.sounds) {
		g.sounds[g.nsounds] = s
		g.nsounds += 1
	}
}

take_sound :: proc(g: ^Game) -> (s: Sound, ok: bool) {
	if g.nsounds == 0 {return}
	s = g.sounds[0]
	for i in 1 ..< g.nsounds {g.sounds[i - 1] = g.sounds[i]}
	g.nsounds -= 1
	return s, true
}

// --- Flow ---------------------------------------------------------------------------------

title :: proc(seed: u64) -> Game {
	g: Game
	g.rng = {seed}
	g.phase = .Title
	return g
}

// A fresh run. The best score and the RNG carry over. The first marker shows at once.
new_game :: proc(g: ^Game) {
	best, rng := g.best, g.rng
	g^ = {}
	g.best, g.rng = best, rng
	g.phase = .Playing
	g.gap = FIRST_GAP
	start_warning(g)
}

start_warning :: proc(g: ^Game) {
	g.warn_t = WARN_TIME
	g.warn_x = RADIUS + 4 + unit(&g.rng) * (LOGICAL_W - 2 * (RADIUS + 4))
	sound(g, .Warn)
}

score_tenths :: proc(g: ^Game) -> int {
	return int(g.time * 10)
}

click :: proc(g: ^Game, x, y: int) {
	switch g.phase {
	case .Title:
		new_game(g)
	case .Over:
		if g.over_t >= OVER_LOCK {new_game(g)}
	case .Playing:
		bop(g, f32(x), f32(y))
	}
}

input :: proc(g: ^Game, a: Action) {
	switch a {
	case .Confirm:
		switch g.phase {
		case .Title:
			new_game(g)
		case .Over:
			if g.over_t >= OVER_LOCK {new_game(g)}
		case .Playing:
		}
	}
}

// Bop the nearest ball within REACH of (x, y). It goes up, and sideways away from the point hit.
// Returns whether a ball was hit.
bop :: proc(g: ^Game, x, y: f32) -> bool {
	g.ripple_x, g.ripple_y, g.ripple_t = x, y, 0.3
	best := -1
	best_d := f32(REACH * REACH)
	for i in 0 ..< g.nballs {
		b := &g.balls[i]
		dx, dy := b.x - x, b.y - y
		d := dx * dx + dy * dy
		if d <= best_d {best, best_d = i, d}
	}
	g.ripple_hit = best >= 0
	if best < 0 {return false}
	b := &g.balls[best]
	side := math.clamp((b.x - x) / REACH, -1, 1)
	b.vx = b.vx * KEEP_VX + side * BOP_VX
	b.vy = -BOP_VY
	b.squash = 0.12
	b.hits += 1
	g.bops += 1
	sound(g, .Bop)
	return true
}

update :: proc(g: ^Game, dt_in: f32) {
	dt := min(dt_in, MAX_DT)
	if g.ripple_t > 0 {g.ripple_t = max(0, g.ripple_t - dt)}
	switch g.phase {
	case .Title:
	case .Over:
		g.over_t += dt
		for i in 0 ..< g.nballs {g.balls[i].squash = max(0, g.balls[i].squash - dt)}
	case .Playing:
		left := dt
		for left > 0 && g.phase == .Playing {
			h := min(left, STEP)
			tick(g, h)
			left -= h
		}
	}
}

@(private)
tick :: proc(g: ^Game, dt: f32) {
	g.time += dt

	// Drops: a marker, then its ball; then the wait until the next marker.
	if g.warn_t > 0 {
		g.warn_t -= dt
		if g.warn_t <= 0 {
			g.warn_t = 0
			if g.nballs < MAX_BALLS {
				g.balls[g.nballs] = {x = g.warn_x, y = -RADIUS, vy = 30}
				g.nballs += 1
				sound(g, .Arrive)
			}
			g.next_drop = g.gap
			g.gap = max(MIN_GAP, g.gap * GAP_SCALE)
		}
	} else if g.nballs < MAX_BALLS {
		g.next_drop -= dt
		if g.next_drop <= 0 {start_warning(g)}
	}

	for i in 0 ..< g.nballs {
		b := &g.balls[i]
		b.squash = max(0, b.squash - dt)
		b.vy += GRAVITY * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		if b.x < RADIUS {
			b.x = RADIUS
			b.vx = abs(b.vx) * WALL_BOUNCE
		} else if b.x > LOGICAL_W - RADIUS {
			b.x = LOGICAL_W - RADIUS
			b.vx = -abs(b.vx) * WALL_BOUNCE
		}
		// The ceiling only pushes back balls already in play (new ones fall in from above it).
		if b.y < RADIUS && b.vy < 0 {
			b.y = RADIUS
			b.vy = -b.vy * CEIL_BOUNCE
		}
	}

	collide(g)

	for i in 0 ..< g.nballs {
		b := &g.balls[i]
		if b.y + RADIUS >= FLOOR_Y {
			b.y = FLOOR_Y - RADIUS
			b.vx, b.vy = 0, 0
			b.squash = 0.4
			game_over(g, i)
			return
		}
	}
}

// Equal-mass balls bounce off each other.
@(private)
collide :: proc(g: ^Game) {
	clack := false
	for i in 0 ..< g.nballs {
		for j in i + 1 ..< g.nballs {
			a, b := &g.balls[i], &g.balls[j]
			dx, dy := b.x - a.x, b.y - a.y
			d2 := dx * dx + dy * dy
			if d2 >= 4 * RADIUS * RADIUS || d2 == 0 {continue}
			d := math.sqrt(d2)
			nx, ny := dx / d, dy / d
			push := (2 * RADIUS - d) / 2
			a.x -= nx * push
			a.y -= ny * push
			b.x += nx * push
			b.y += ny * push
			rel := (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
			if rel < 0 {
				k := -(1 + BALL_BOUNCE) * rel / 2
				a.vx -= k * nx
				a.vy -= k * ny
				b.vx += k * nx
				b.vy += k * ny
				if rel < -40 {clack = true}
			}
		}
	}
	if clack {sound(g, .Clack)}
}

@(private)
game_over :: proc(g: ^Game, i: int) {
	g.phase = .Over
	g.dropped = i
	g.over_t = 0
	g.warn_t = 0
	sound(g, .Drop)
	s := score_tenths(g)
	if s > g.best && !g.demo {
		g.best = s
		g.new_best = true
		g.save_best = true
		sound(g, .Record)
	}
}

// A deadpan remark for the result screen, by how long the run lasted.
remark :: proc(g: ^Game) -> string {
	switch {
	case g.time < 10: return "That was quick."
	case g.time < 30: return "It happens to everyone."
	case g.time < 60: return "Respectable stamina."
	case g.time < 120: return "Impressive restraint."
	}
	return "Okay, show-off."
}

// QA: a fixed mid-run scene (five balls in the air, a marker showing) for screenshots.
demo :: proc(g: ^Game) {
	new_game(g)
	g.demo = true
	g.time = 41.7
	g.gap = 3.4
	g.nballs = 5
	g.balls[0] = {x = 30, y = 60, vx = 20, vy = -40}
	g.balls[1] = {x = 70, y = 150, vx = -10, vy = 90}
	g.balls[2] = {x = 105, y = 95, vx = 0, vy = -120, squash = 0.1}
	g.balls[3] = {x = 135, y = 190, vx = -30, vy = 140}
	g.balls[4] = {x = 52, y = 118, vx = 40, vy = 10}
	g.warn_t = WARN_TIME
	g.warn_x = 120
	g.nsounds = 0
}

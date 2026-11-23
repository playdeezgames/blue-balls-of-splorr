// Blue Balls of SPLORR!!: rules and state. No drawing and no JS; the web layer reads this and draws it.
//
// Blue balls fall under gravity. Click or tap one to bop it upward, away from the point you hit.
// A new ball drops in on a timer that shortens each time. When any ball touches the floor, the run
// is over. There is no win: the score is how long you kept them up.
// Design decisions are recorded in the vault: splorr/Games/Blue Balls of SPLORR!!.md.
package game

import "core:math"
import ll "bbs:src/lootlocker"

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
BOARD_KEY :: "blue_balls_longest" // tenths of a second; the page adds _test for ?board=test
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
	Confirm, // Enter, Space, pad A or Start
	Back, // Escape, pad B
}

Phase :: enum {
	Title,
	Playing,
	Over,
	Name, // typing a name for the board
	Scores, // the online board
}

// Tap targets in the floor bar (y FLOOR_Y..LOGICAL_H), split into a left and a right half.
Button :: enum {
	None,
	Left,
	Right,
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
	save_name:  bool, // the web layer stores g.name
	ripple_x:   f32, // the last tap, for a little ring
	ripple_y:   f32,
	ripple_t:   f32,
	ripple_hit: bool,
	demo:       bool, // a QA scene: its run never counts as a best
	name:       ll.Name_Edit, // the player's board name (empty until they give one)
	edit:       ll.Name_Edit, // the name being typed on the Name screen
	pending:    int, // tenths: the best unsent run, waiting for a name
	after_name: Phase, // where the Name screen goes when done
	refresh_on: bool, // the Scores screen reloads once the submit in flight is answered
	sent:       bool, // this run's time went to the board (or is going)
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
	keep := g^
	g^ = {}
	g.best, g.rng, g.name, g.pending = keep.best, keep.rng, keep.name, keep.pending
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

has_name :: proc(g: ^Game) -> bool {
	return g.name.len > 0
}

// The floor-bar button under a tap, if any.
button_at :: proc(x, y: int) -> Button {
	if y < FLOOR_Y {return .None}
	return x < LOGICAL_W / 2 ? .Left : .Right
}

// A run's result screen asks for a name when there is a time to send and no name yet.
wants_name :: proc(g: ^Game) -> bool {
	return !has_name(g) && g.pending > 0
}

click :: proc(g: ^Game, x, y: int) {
	switch g.phase {
	case .Title:
		switch button_at(x, y) {
		case .None: new_game(g)
		case .Left: open_scores(g)
		case .Right: open_name(g, .Title)
		}
	case .Over:
		if g.over_t < OVER_LOCK {return}
		switch button_at(x, y) {
		case .None, .Left:
			if wants_name(g) {open_name(g, .Scores)} else {new_game(g)}
		case .Right:
			if wants_name(g) {new_game(g)} else {open_scores(g)} // Right is "skip" while asking for a name
		}
	case .Name:
		switch button_at(x, y) {
		case .None: // the page re-opens the keyboard
		case .Left: finish_name(g)
		case .Right: leave_name(g)
		}
	case .Scores:
		g.phase = .Title
	case .Playing:
		bop(g, f32(x), f32(y))
	}
}

input :: proc(g: ^Game, a: Action) {
	switch g.phase {
	case .Title:
		if a == .Confirm {new_game(g)}
	case .Over:
		if g.over_t < OVER_LOCK {return}
		if a == .Confirm {
			if wants_name(g) {open_name(g, .Scores)} else {new_game(g)}
		} else {
			g.phase = .Title
		}
	case .Name:
		if a == .Confirm {finish_name(g)} else {leave_name(g)}
	case .Scores:
		g.phase = .Title
	case .Playing:
	}
}

// --- The board ----------------------------------------------------------------------------

open_scores :: proc(g: ^Game) {
	g.phase = .Scores
	if ll.board.submit == .Sending {
		g.refresh_on = true
		ll.board.status = .Loading
	} else {
		ll.refresh(BOARD_KEY)
	}
}

open_name :: proc(g: ^Game, after: Phase) {
	g.edit = g.name
	g.after_name = after
	g.phase = .Name
}

name_char :: proc(g: ^Game, c: u8) {
	if g.phase == .Name {ll.name_type(&g.edit, c)}
}

name_backspace :: proc(g: ^Game) {
	if g.phase == .Name {ll.name_backspace(&g.edit)}
}

name_clear :: proc(g: ^Game) {
	if g.phase == .Name {g.edit.len = 0}
}

// Keep the typed name (if there is one) and send any time that was waiting for it.
finish_name :: proc(g: ^Game) {
	if _, ok := ll.name_finish(&g.edit); !ok {return}
	g.name = g.edit
	g.save_name = true
	ll.set_name(ll.name_text(&g.name))
	if g.pending > 0 {
		ll.submit(BOARD_KEY, g.pending)
		g.pending = 0
	}
	if g.after_name == .Scores {open_scores(g)} else {g.phase = g.after_name}
}

leave_name :: proc(g: ^Game) {
	g.phase = .Title
}

// Called when a run ends: a named player's time goes straight to the board; otherwise it waits.
@(private)
send_run :: proc(g: ^Game, tenths: int) {
	if tenths <= 0 {return}
	if has_name(g) {
		ll.submit(BOARD_KEY, tenths)
		g.sent = true
	} else {
		g.pending = max(g.pending, tenths)
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
	case .Title, .Name:
	case .Scores:
		if g.refresh_on && ll.board.submit != .Sending {
			g.refresh_on = false
			ll.refresh(BOARD_KEY)
		}
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
	if !g.demo {send_run(g, s)}
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

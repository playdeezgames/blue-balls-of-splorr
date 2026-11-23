// Thin browser layer: input, drawing and the frame loop. Rules and state live in package game.
#+build js
package main

import "base:runtime"
import "core:time"
import "bbs:game"
import ll "bbs:src/lootlocker"

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	// rgb is 0xRRGGBB; coordinates are logical pixels, y down.
	fill_rect :: proc(x, y, w, h: f32, rgb: u32, alpha: f32) ---
	// A blue ball centred at x, y. squash 0..1 flattens it; danger 0..1 deepens the blue.
	ball :: proc(x, y, r, squash, danger: f32) ---
	// A soft floor shadow centred at x with half-width w.
	shadow :: proc(x, w, alpha: f32) ---
	ring :: proc(x, y, r: f32, rgb: u32, alpha: f32) ---
	play_sound :: proc(sound: i32) ---
	// Bitmap text (m5x7). y is the baseline; scale is a whole number; x is the centre when centered.
	draw_text :: proc(x, y: f32, text: string, rgb: u32, scale: i32, centered: bool) ---
	load_best :: proc() -> i32 ---
	// The saved board name, written into buf; returns its length.
	load_name :: proc(buf: rawptr, cap: i32) -> i32 ---
	save_name :: proc(name: string) ---
	// Show or hide the text box that brings up the phone keyboard (only works inside a tap or key press).
	name_keyboard :: proc(on: bool) ---
	save_best :: proc(score: i32) ---
}

PAPER :: 0xf2ece0
FLOOR :: 0x2a2633
INK :: 0x2a2633
DIM :: 0x8a8394
BLUE :: 0x2f5fd8
RED :: 0xc8402e

ctx: runtime.Context
state: game.Game
blink_t: f64 // half-seconds, for the name cursor

main :: proc() {
	ctx = context
	state = game.title(u64(time.now()._nsec))
	state.best = int(load_best())
	buf: [ll.NAME_LEN]u8
	n := clamp(int(load_name(&buf, ll.NAME_LEN)), 0, ll.NAME_LEN)
	ll.name_load(&state.name, string(buf[:n]))
	if state.name.len > 0 {ll.set_name(ll.name_text(&state.name))}
}

// After a tap or key press (a user gesture) the keyboard can open; it follows the Name screen.
@(private)
keyboard_follow :: proc() {
	name_keyboard(state.phase == .Name)
}

@(export)
click :: proc "c" (x, y: i32) {
	context = ctx
	game.click(&state, int(x), int(y))
	keyboard_follow()
}

@(export)
input :: proc "c" (action: i32) {
	context = ctx
	game.input(&state, game.Action(action))
	keyboard_follow()
}

// Typing on the Name screen: the page forwards each character, Backspace and a clear.
@(export)
type_char :: proc "c" (c: i32) {
	context = ctx
	if c > 0 && c < 128 {game.name_char(&state, u8(c))}
}

@(export)
type_backspace :: proc "c" () {
	context = ctx
	game.name_backspace(&state)
}

@(export)
type_clear :: proc "c" () {
	context = ctx
	game.name_clear(&state)
}

// QA: a fixed mid-run scene for screenshots. index.html calls it for ?demo.
@(export)
qa_demo :: proc "c" () {
	context = ctx
	game.demo(&state)
}

// QA: advance the game by secs in 60 Hz frames and draw, for testing in a browser that is not running frames.
@(export)
qa_advance :: proc "c" (secs: f32) {
	context = ctx
	for t: f32 = 0; t < secs; t += 1.0 / 60 {game.update(&state, 1.0 / 60)}
	draw() // so a capture right after sees this state, even while the page is not running frames
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	blink_t += dt * 2
	game.update(&state, f32(dt))
	if state.save_best {
		save_best(i32(state.best))
		state.save_best = false
	}
	if state.save_name {
		save_name(ll.name_text(&state.name))
		state.save_name = false
	}
	if state.phase != .Name {name_keyboard(false)}
	for {
		s, ok := game.take_sound(&state)
		if !ok {break}
		play_sound(i32(s))
	}
	draw()
	return true
}

draw_play :: proc(g: ^game.Game) {
	fill_rect(0, game.FLOOR_Y, game.LOGICAL_W, game.LOGICAL_H - game.FLOOR_Y, FLOOR, 1)

	for i in 0 ..< g.nballs {
		b := g.balls[i]
		h := clamp((game.FLOOR_Y - b.y) / game.FLOOR_Y, 0, 1)
		shadow(b.x, game.RADIUS * (1.1 - 0.6 * h), 0.35 * (1 - h) + 0.05)
	}

	if g.warn_t > 0 && g.phase == .Playing {
		// A falling-ball marker at the top edge, blinking faster as it nears.
		blink := int(g.warn_t * (g.warn_t < 0.5 ? 16 : 8)) % 2 == 0
		if blink {
			fill_rect(g.warn_x - 1, 2, 3, 7, RED, 1)
			fill_rect(g.warn_x - 1, 11, 3, 2, RED, 1)
		}
	}

	for i in 0 ..< g.nballs {
		b := g.balls[i]
		danger := clamp((b.y - 120) / (game.FLOOR_Y - game.RADIUS - 120), 0, 1)
		if b.vy < 0 {danger *= 0.4}
		sq := b.squash > 0 ? min(1, b.squash / 0.12) : 0
		if g.phase == .Over && i == g.dropped {sq = 1; danger = 1}
		ball(b.x, b.y, game.RADIUS, sq, danger)
	}

	if g.ripple_t > 0 {
		k := g.ripple_t / 0.3
		ring(g.ripple_x, g.ripple_y, game.REACH * (1.2 - 0.6 * k), g.ripple_hit ? BLUE : DIM, k * 0.8)
	}
}

// The floor bar with a label on each half (an empty label leaves that half blank).
bar :: proc(left, right: string) {
	fill_rect(0, game.FLOOR_Y, game.LOGICAL_W, game.LOGICAL_H - game.FLOOR_Y, FLOOR, 1)
	fill_rect(game.LOGICAL_W / 2, game.FLOOR_Y + 3, 1, game.LOGICAL_H - game.FLOOR_Y - 6, DIM, 0.6)
	y := f32(game.FLOOR_Y + 11)
	if left != "" {draw_text(game.LOGICAL_W / 4, y, left, PAPER, 1, true)}
	if right != "" {draw_text(game.LOGICAL_W * 3 / 4, y, right, PAPER, 1, true)}
}

draw :: proc() {
	g := &state
	fill_rect(0, 0, game.LOGICAL_W, game.LOGICAL_H, PAPER, 1)
	cx :: f32(game.LOGICAL_W / 2)
	buf: [32]u8

	switch g.phase {
	case .Title:
		ball(cx - 22, 150, game.RADIUS, 0, 0)
		ball(cx + 22, 150, game.RADIUS, 0, 0)
		draw_text(cx, 48, "BLUE BALLS", BLUE, 2, true)
		draw_text(cx, 64, "of SPLORR!!", INK, 1, true)
		draw_text(cx, 92, "Tap a ball to bop it up.", INK, 1, true)
		draw_text(cx, 104, "More keep coming.", INK, 1, true)
		draw_text(cx, 116, "Don't let them drop.", INK, 1, true)
		draw_text(cx, 186, "tap to begin", BLUE, 1, true)
		if g.best > 0 {
			draw_text(cx, 200, tenths(&buf, "longest: ", g.best, "s"), DIM, 1, true)
		}
		if g.name.len > 0 {
			draw_text(cx, 212, ll.name_text(&g.name), DIM, 1, true)
		}
		bar("SCORES", g.name.len > 0 ? "RENAME" : "NAME")
	case .Playing, .Over:
		draw_play(g)
		draw_text(cx, 12, tenths(&buf, "", game.score_tenths(g), "s"), INK, 1, true)
		nb: [32]u8
		draw_text(game.LOGICAL_W - 4 - 18, 12, count(&nb, "x", g.nballs), DIM, 1, false)
		if g.phase == .Over {
			fill_rect(0, 70, game.LOGICAL_W, 90, PAPER, 0.88)
			draw_text(cx, 92, "RELEASED.", RED, 2, true)
			draw_text(cx, 108, tenths(&buf, "You kept it up for ", game.score_tenths(g), "s."), INK, 1, true)
			draw_text(cx, 120, game.remark(g), DIM, 1, true)
			if g.new_best {
				draw_text(cx, 134, "Your longest yet.", BLUE, 1, true)
			} else if g.best > 0 {
				bb: [32]u8
				draw_text(cx, 134, tenths(&bb, "longest: ", g.best, "s"), DIM, 1, true)
			}
			if game.wants_name(g) {
				draw_text(cx, 150, "Sign the board?", BLUE, 1, true)
			} else if g.sent {
				msg := "sending to the board..."
				#partial switch ll.board.submit {
				case .Sent: msg = "on the board."
				case .Failed: msg = "the board is out of reach."
				}
				draw_text(cx, 150, msg, DIM, 1, true)
			}
			if g.over_t >= game.OVER_LOCK {
				if game.wants_name(g) {bar("SIGN", "SKIP")} else {bar("AGAIN", "SCORES")}
			}
		}
	case .Name:
		draw_text(cx, 48, "WHO KEPT IT UP?", BLUE, 1, true)
		draw_text(cx, 64, "Your name for the board.", DIM, 1, true)
		fill_rect(8, 80, game.LOGICAL_W - 16, 18, 0xffffff, 1)
		fill_rect(8, 97, game.LOGICAL_W - 16, 1, INK, 1)
		name := ll.name_text(&g.edit)
		draw_text(cx, 93, name, INK, 1, true)
		if int(blink_t) % 2 == 0 {
			draw_text(cx + f32(len(name)) * 2.5 + 3, 93, "_", BLUE, 1, false)
		}
		draw_text(cx, 116, "Tap the box to type.", DIM, 1, true)
		draw_text(cx, 128, "Letters, digits, dashes.", DIM, 1, true)
		if g.pending > 0 {
			draw_text(cx, 148, tenths(&buf, "Your ", g.pending, "s goes up with it."), INK, 1, true)
		}
		bar(g.edit.len > 0 ? "OK" : "", "CANCEL")
	case .Scores:
		draw_text(cx, 22, "LONGEST HELD", BLUE, 2, true)
		switch ll.board.status {
		case .Idle, .Loading:
			draw_text(cx, 110, "asking the board...", DIM, 1, true)
		case .Failed:
			draw_text(cx, 104, "The board is out of reach.", DIM, 1, true)
			draw_text(cx, 116, "Play on; it keeps.", DIM, 1, true)
		case .Ready:
			if ll.board.count == 0 {
				draw_text(cx, 110, "Nobody yet. Be first.", DIM, 1, true)
			}
			for i in 0 ..< ll.board.count {
				e := &ll.board.rows[i]
				y := f32(48 + i * 16)
				colour: u32 = e.mine ? BLUE : INK
				if e.mine {fill_rect(4, y - 10, game.LOGICAL_W - 8, 14, BLUE, 0.12)}
				rb: [32]u8
				draw_text(8, y, count(&rb, "", i + 1), DIM, 1, false)
				draw_text(22, y, ll.entry_name(e), colour, 1, false)
				sb: [32]u8
				s := tenths(&sb, "", e.score, "s")
				draw_text(game.LOGICAL_W - 6 - f32(len(s)) * 5, y, s, colour, 1, false)
			}
		}
		bar("BACK", "")
	}
}

digits :: proc(out: []u8, n: int) -> int {
	tmp: [16]u8
	i := len(tmp)
	v := n
	if v == 0 {
		i -= 1
		tmp[i] = '0'
	}
	for v > 0 && i > 0 {
		i -= 1
		tmp[i] = u8('0' + v % 10)
		v /= 10
	}
	return copy(out, tmp[i:])
}

// prefix, a decimal count.
count :: proc(buf: ^[32]u8, prefix: string, n: int) -> string {
	k := copy(buf[:], prefix)
	k += digits(buf[k:], n)
	return string(buf[:k])
}

// prefix, t tenths written as "12.3", suffix.
tenths :: proc(buf: ^[32]u8, prefix: string, t: int, suffix: string) -> string {
	k := copy(buf[:], prefix)
	k += digits(buf[k:], t / 10)
	k += copy(buf[k:], ".")
	k += digits(buf[k:], t % 10)
	k += copy(buf[k:], suffix)
	return string(buf[:k])
}

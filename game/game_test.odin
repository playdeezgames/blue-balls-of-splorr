#+build !js
package game

import ll "bbs:src/lootlocker"
import "core:testing"

@(private = "file")
one_ball :: proc(x, y: f32) -> Game {
	g := title(1)
	new_game(&g)
	g.warn_t = 0
	g.next_drop = 1000
	g.nballs = 1
	g.balls[0] = {x = x, y = y}
	g.nsounds = 0
	return g
}

// Run for secs in 60 Hz frames (update clamps a long frame).
@(private = "file")
run :: proc(g: ^Game, secs: f32) {
	for t: f32 = 0; t < secs; t += 1.0 / 60 {update(g, 1.0 / 60)}
}

@(test)
first_ball_arrives_after_the_marker :: proc(t: ^testing.T) {
	g := title(7)
	new_game(&g)
	testing.expect_value(t, g.nballs, 0)
	run(&g, WARN_TIME - 0.05)
	testing.expect_value(t, g.nballs, 0)
	run(&g, 0.1)
	testing.expect_value(t, g.nballs, 1)
}

@(test)
bop_sends_the_ball_up_and_away_from_the_tap :: proc(t: ^testing.T) {
	g := one_ball(80, 100)
	testing.expect(t, bop(&g, 75, 100)) // tapped on its left: it goes right
	testing.expect(t, g.balls[0].vy < 0)
	testing.expect(t, g.balls[0].vx > 0)
	g2 := one_ball(80, 100)
	bop(&g2, 85, 100)
	testing.expect(t, g2.balls[0].vx < 0)
}

@(test)
a_tap_out_of_reach_misses :: proc(t: ^testing.T) {
	g := one_ball(80, 100)
	testing.expect(t, !bop(&g, 80 + REACH + 1, 100))
	testing.expect_value(t, g.bops, 0)
}

@(test)
an_untouched_ball_drops_and_ends_the_run :: proc(t: ^testing.T) {
	g := one_ball(80, 40)
	for _ in 0 ..< 200 {update(&g, 1.0 / 60)}
	testing.expect_value(t, g.phase, Phase.Over)
	testing.expect(t, g.best > 0)
	testing.expect(t, g.save_best)
}

@(test)
a_frantic_tap_right_after_the_drop_does_not_restart :: proc(t: ^testing.T) {
	g := one_ball(80, FLOOR_Y - RADIUS - 1)
	run(&g, 0.2)
	testing.expect_value(t, g.phase, Phase.Over)
	click(&g, 80, 100)
	testing.expect_value(t, g.phase, Phase.Over)
	run(&g, OVER_LOCK)
	click(&g, 80, 100)
	testing.expect_value(t, g.phase, Phase.Playing)
}

@(test)
gaps_shrink_to_the_minimum :: proc(t: ^testing.T) {
	g := title(3)
	new_game(&g)
	gap := f32(FIRST_GAP)
	for _ in 0 ..< 40 {gap = max(MIN_GAP, gap * GAP_SCALE)}
	testing.expect_value(t, gap, f32(MIN_GAP))
}

@(test)
walls_keep_balls_on_screen :: proc(t: ^testing.T) {
	g := one_ball(20, 60)
	g.balls[0].vx = -100
	g.balls[0].vy = -200
	for _ in 0 ..< 30 {update(&g, 1.0 / 60)}
	testing.expect(t, g.balls[0].x >= RADIUS)
	testing.expect(t, g.balls[0].vx > 0)
}

@(private = "file")
drop_now :: proc(g: ^Game) {
	g.time = 12.3
	g.balls[0].y = FLOOR_Y - RADIUS - 0.5
	g.balls[0].vy = 50
	run(g, 0.1)
}

@(test)
an_unnamed_run_waits_for_a_name_then_goes_up_with_it :: proc(t: ^testing.T) {
	g := one_ball(80, 100)
	drop_now(&g)
	testing.expect_value(t, g.phase, Phase.Over)
	testing.expect(t, wants_name(&g))
	testing.expect(t, !g.sent)
	run(&g, OVER_LOCK)
	click(&g, 40, 100) // anywhere but SKIP: sign the board
	testing.expect_value(t, g.phase, Phase.Name)
	for c in transmute([]u8)string("dr who!") {name_char(&g, c)}
	click(&g, 20, FLOOR_Y + 4) // OK
	testing.expect_value(t, ll_text(&g.name), "DR WHO")
	testing.expect(t, g.save_name)
	testing.expect_value(t, g.pending, 0)
	testing.expect_value(t, g.phase, Phase.Scores)
}

@(test)
skip_keeps_the_time_for_later_and_starts_again :: proc(t: ^testing.T) {
	g := one_ball(80, 100)
	drop_now(&g)
	run(&g, OVER_LOCK)
	click(&g, 140, FLOOR_Y + 4) // SKIP
	testing.expect_value(t, g.phase, Phase.Playing)
	testing.expect(t, g.pending > 0)
}

@(test)
a_named_players_run_is_sent_at_once :: proc(t: ^testing.T) {
	g := one_ball(80, 100)
	for c in transmute([]u8)string("ACE") {g.name.buf[g.name.len] = c; g.name.len += 1}
	drop_now(&g)
	testing.expect(t, g.sent)
	testing.expect(t, !wants_name(&g))
	testing.expect_value(t, g.pending, 0)
}

@(test)
an_empty_name_is_not_accepted :: proc(t: ^testing.T) {
	g := title(1)
	open_name(&g, .Title)
	name_char(&g, ' ')
	finish_name(&g)
	testing.expect_value(t, g.phase, Phase.Name)
}

@(private = "file")
ll_text :: proc(e: ^ll.Name_Edit) -> string {
	return ll.name_text(e)
}

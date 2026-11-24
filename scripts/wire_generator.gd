class_name WireGenerator
extends Node2D
## Builds poles, sagging wire lanes and perched/flying birds ahead of the camera.
## Wire height is a pure function of x (see wire_y_at), so the runner can sample it.
## Wire presence is decided per span by a sequential weighted run generator (wire run / street run
## alternating); has_wire() is the single source of truth for where wire exists.

@export var span := 640.0                 ## distance between poles
@export var sag := 46.0                   ## mid-span dip in px
@export var lane_y: Array[float] = [250.0]   ## one wire per pole (multi-lane still supported)
@export var floor_y := 620.0              ## y of the street surface (feet / car bottoms)
@export_group("Birds")
@export var bird_chance := 0.65           ## per span
@export var bird_weight_single := 0.35    ## one perched bird
@export var bird_weight_line := 0.3       ## 2-4 perched birds lined up on the wire
@export var bird_weight_flying := 0.35    ## flying mid-air (also over street runs)
@export var bird_line_gap_min := 64.0
@export var bird_line_gap_max := 96.0
@export var bird_fly_speed_min := 60.0    ## px/s toward the runner (world space)
@export var bird_fly_speed_max := 170.0
@export var bird_weight_wave := 0.14      ## 3-4 flying birds in a diagonal staircase (slice chain)
@export var bird_weight_combo := 0.14     ## perched line + one flyer above/ahead of it (needs wire)
@export var wave_min_span := 6            ## no waves before this span
@export var bridge_chance := 0.5          ## 1-span street gaps: a low flyer mid-gap to bounce across
@export var repeat_damp := 0.3            ## weight factor for repeating the previous span's pattern
@export var bird_fly_y_min := 190.0       ## feet y of flying birds
@export var bird_fly_y_max := 540.0
@export var bird_fly_y_street := 400.0    ## over street spans flyers stay low (bounce targets)
@export_group("Frenzy")
@export var frenzy_chance := 0.3          ## chance a wire run is a long bird-packed "frenzy" run
@export var frenzy_min_span := 10         ## none before this span index
@export var frenzy_len_min := 5           ## spans (first and last are bird-free lead-in/out)
@export var frenzy_len_max := 8
@export var frenzy_gap_min := 85.0        ## px between birds
@export var frenzy_gap_max := 125.0
@export_group("Gauntlet")
@export var gauntlet_chance := 0.15       ## chance a (non-frenzy) wire run is a transformer gauntlet
@export var gauntlet_min_span := 12
@export var gauntlet_len_min := 3         ## spans; every interior pole carries a transformer
@export var gauntlet_len_max := 5
@export_group("")
@export var safe_spans := 2               ## no birds in the first spans
@export var obstacle_chance_easy := 0.2   ## share of eligible poles with a transformer, at the start...
@export var obstacle_chance_hard := 0.45  ## ...and at full difficulty
@export var seed_value := 1337
@export_group("Wire runs")
@export var opening_min := 3              ## guaranteed wire spans at the start (rolled per round)
@export var opening_max := 6
@export var wire_min := 3                 ## spans
@export var wire_max_easy := 8
@export var wire_max_hard := 4
@export var street_min := 1               ## spans without wire
@export var street_max_easy := 2
@export var street_max_hard := 4
@export var difficulty_spans := 60.0      ## spans until difficulty is maxed
@export var safe_after_end := 700.0       ## no street hazards this far past a wire end (landing window)
@export var safe_before_end := 100.0
@export var safe_before_return := 500.0   ## ...nor this far before wire returns (jump-up window)
@export var safe_after_return := 100.0

const POINT_STEP := 20.0

var _spans: Dictionary = {}               ## span index -> Node2D container
var _span_wire: Array[bool] = []          ## span index (>= 0) -> wire present; extended sequentially
var _span_kind: Array[int] = []           ## span index -> SpanKind, parallel to _span_wire
var _span_birds: Array[int] = []          ## span index -> BirdPattern, parallel to _span_wire
enum SpanKind { NORMAL, FRENZY, FRENZY_EDGE, GAUNTLET }
enum BirdPattern { NONE, SINGLE, LINE, FLYING, WAVE, COMBO, BRIDGE }
var _rng := RandomNumberGenerator.new()
var _last_run_wire := true
var _last_special := false                ## previous wire run was a frenzy/gauntlet (no two in a row)
var _frenzy_from := 10                    ## rolled per round from frenzy_min_span

## Per-round "mood": silently shifts the generator/traffic mix (picked by Game from the round seed).
enum Mood { NORMAL, BIRDY, RUSH_HOUR, LIVE_WIRES, CALM }
const MOOD_WEIGHTS := [0.4, 0.15, 0.15, 0.15, 0.15]   ## indexed by Mood


static func pick_mood(rng: RandomNumberGenerator) -> Mood:
	var pick := rng.randf() * 1.0
	for m in MOOD_WEIGHTS.size():
		pick -= MOOD_WEIGHTS[m]
		if pick < 0.0:
			return m as Mood
	return Mood.NORMAL


## Scales this generator's and the traffic's tunables for the round. Call before the first span is built.
func apply_mood(m: Mood, traffic: Traffic) -> void:
	match m:
		Mood.BIRDY:
			bird_chance *= 1.3
			bird_weight_flying *= 1.4
			bird_weight_wave *= 1.6
			frenzy_chance = 0.45
		Mood.RUSH_HOUR:
			traffic.gap_min *= 0.75
			traffic.gap_max *= 0.75
			traffic.chain_chance = 0.7
			traffic.big_chance *= 1.5
			street_max_easy += 1
			street_max_hard += 1
		Mood.LIVE_WIRES:
			obstacle_chance_easy += 0.12
			obstacle_chance_hard += 0.12
			gauntlet_chance *= 2.0
		Mood.CALM:
			wire_max_easy += 2
			wire_max_hard += 2
			street_max_easy = maxi(street_min, street_max_easy - 1)
			street_max_hard = maxi(street_min, street_max_hard - 1)
			bird_weight_line *= 1.4
			bird_weight_wave *= 1.5


func lane_count() -> int:
	return lane_y.size()


func wire_y_at(lane: int, x: float) -> float:
	var t := fposmod(x, span) / span
	return lane_y[lane] + sag * 4.0 * t * (1.0 - t)


## dy/dx of the wire; positive = downhill (screen y grows downward).
func slope_at(lane: int, x: float) -> float:
	var t := fposmod(x, span) / span
	return sag * 4.0 * (1.0 - 2.0 * t) / span


func span_index(x: float) -> int:
	return int(floorf(x / span))


## Is there wire (all lanes) above x?
func has_wire_at(x: float) -> bool:
	return has_wire(span_index(x))


## Is span i part of a bird-packed frenzy run (not its bird-free lead-in/out)?
func is_frenzy(i: int) -> bool:
	if i < 0:
		return false
	_extend_runs(i)
	return _span_kind[i] == SpanKind.FRENZY


func has_wire(i: int) -> bool:
	if i < 0:
		return true
	_extend_runs(i)
	return _span_wire[i]


## Poles stand at span boundaries next to any wire; none in the middle of a street run.
func has_pole(i: int) -> bool:
	return has_wire(i) or has_wire(i - 1)


## Pole-top transformer (touching it electrocutes). Only on some poles: wire on both sides (never where
## the wire ends or returns), never in a frenzy run, none at the start, deterministic per-pole roll that
## gets likelier with difficulty.
func has_obstacle(i: int) -> bool:
	if i < safe_spans + 2 or not (has_wire(i) and has_wire(i - 1)):
		return false
	if is_frenzy(i) or is_frenzy(i - 1):
		return false
	if _span_kind[i] == SpanKind.GAUNTLET and _span_kind[i - 1] == SpanKind.GAUNTLET:
		return true                                                # interior gauntlet pole
	var chance := lerpf(obstacle_chance_easy, obstacle_chance_hard, clampf(i / difficulty_spans, 0.0, 1.0))
	return float(hash(Vector2i(i, seed_value + 7)) % 10000) / 10000.0 < chance


## Crossarm/insulator obstacle sitting on the top wire at the nearest pole (empty rect if no pole).
func pole_rect_near(x: float) -> Rect2:
	var i := int(roundf(x / span))
	if not has_obstacle(i):
		return Rect2()
	var px := i * span
	return Rect2(px - 16.0, lane_y[0] - 34.0, 32.0, 34.0)


## True if street hazards (cars/peds) may meet the runner at world x. Keeps a clear landing window
## after a wire ends and a clear jump-up window before it returns.
func street_hazard_ok(x: float) -> bool:
	var i := span_index(x)
	for b in range(i - 2, i + 3):
		var before := has_wire(b - 1)
		var after := has_wire(b)
		var bx := b * span
		if before and not after and x > bx - safe_before_end and x < bx + safe_after_end:
			return false
		if after and not before and x > bx - safe_before_return and x < bx + safe_after_return:
			return false
	return true


func _extend_runs(upto: int) -> void:
	if _span_wire.is_empty():
		_rng.seed = seed_value
		_last_run_wire = true
		var opening := _rng.randi_range(opening_min, opening_max)
		_frenzy_from = maxi(frenzy_min_span + _rng.randi_range(-3, 4), opening + 2)
		for k in opening:
			_append_span(true, SpanKind.NORMAL, 1)
	while _span_wire.size() <= upto:
		var at := _span_wire.size()
		var d := clampf(at / difficulty_spans, 0.0, 1.0)
		_last_run_wire = not _last_run_wire
		var n: int
		var special_ok := _last_run_wire and not _last_special
		var frenzy := special_ok and at >= _frenzy_from and _rng.randf() < frenzy_chance
		var gauntlet := special_ok and not frenzy and at >= gauntlet_min_span and _rng.randf() < gauntlet_chance
		if _last_run_wire:
			_last_special = frenzy or gauntlet
		if frenzy:
			n = _rng.randi_range(frenzy_len_min, frenzy_len_max)
		elif gauntlet:
			n = _rng.randi_range(gauntlet_len_min, gauntlet_len_max)
		elif _last_run_wire:
			var mx := maxi(wire_min, roundi(lerpf(wire_max_easy, wire_max_hard, d)))
			n = wire_min + int(pow(_rng.randf(), 1.0 + d) * (mx - wire_min + 1))
			n = mini(n, mx)
		else:
			var mx := maxi(street_min, roundi(lerpf(street_max_easy, street_max_hard, d)))
			n = street_min + int(pow(_rng.randf(), 1.3) * (mx - street_min + 1))
			n = mini(n, mx)
		for k in n:
			var kind := SpanKind.NORMAL
			if frenzy:
				kind = SpanKind.FRENZY_EDGE if k == 0 or k == n - 1 else SpanKind.FRENZY
			elif gauntlet:
				kind = SpanKind.GAUNTLET
			_append_span(_last_run_wire, kind, n)


## Appends one span and picks its bird pattern from the sequential rng (so it can avoid repeating the
## previous span's pattern). run_len = length of the run the span belongs to.
func _append_span(wire: bool, kind: SpanKind, run_len: int) -> void:
	var at := _span_wire.size()
	_span_wire.append(wire)
	_span_kind.append(kind)
	_span_birds.append(_pick_pattern(at, wire, kind, run_len))


func _pick_pattern(at: int, wire: bool, kind: SpanKind, run_len: int) -> BirdPattern:
	if at < safe_spans or kind == SpanKind.FRENZY or kind == SpanKind.FRENZY_EDGE:
		return BirdPattern.NONE                                    # frenzy spans are filled by _spawn_birds
	if kind == SpanKind.GAUNTLET:                                  # transformers are the hazard; maybe a high flyer
		return BirdPattern.FLYING if _rng.randf() < 0.35 else BirdPattern.NONE
	if not wire and run_len == 1 and _rng.randf() < bridge_chance:
		return BirdPattern.BRIDGE
	if _rng.randf() >= minf(bird_chance * TimeOfDay.p().birds, 0.95):   # dawn has more birds, night fewer
		return BirdPattern.NONE
	var weights := {
		BirdPattern.SINGLE: bird_weight_single if wire else 0.0,
		BirdPattern.LINE: bird_weight_line if wire else 0.0,
		BirdPattern.COMBO: bird_weight_combo if wire else 0.0,
		BirdPattern.FLYING: bird_weight_flying,
		BirdPattern.WAVE: bird_weight_wave if at >= wave_min_span else 0.0,
	}
	var prev: int = _span_birds[at - 1] if at > 0 else BirdPattern.NONE
	if weights.has(prev):
		weights[prev] *= repeat_damp
	var total := 0.0
	for w in weights.values():
		total += w
	var pick := _rng.randf() * total
	for p in weights:
		pick -= weights[p]
		if pick < 0.0:
			return p
	return BirdPattern.FLYING


func update_spans(left: float, right: float) -> void:
	var first := int(floorf(left / span)) - 1
	var last := int(floorf(right / span)) + 1
	for i in range(first, last + 1):
		if not _spans.has(i):
			_spans[i] = _build_span(i)
	for i in _spans.keys():
		if i < first:
			(_spans[i] as Node2D).queue_free()
			_spans.erase(i)


func _build_span(i: int) -> Node2D:
	var c := Node2D.new()
	add_child(c)
	var x0 := i * span

	if has_pole(i):
		var pole := Pole.new()
		pole.position = Vector2(x0, 0)
		pole.top_y = lane_y[0]
		pole.bottom_y = floor_y
		pole.lane_ys = lane_y
		pole.obstacle = has_obstacle(i)
		c.add_child(pole)

	_spawn_birds(c, i, x0)

	if not has_wire(i):
		return c

	for l in lane_count():
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = TimeOfDay.p().wire
		var x := x0
		while x < x0 + span:
			line.add_point(Vector2(x, wire_y_at(l, x)))
			x += POINT_STEP
		line.add_point(Vector2(x0 + span, wire_y_at(l, x0 + span)))
		c.add_child(line)

	return c


## Per-span bird roll (deterministic per span): nothing, one perched bird, a line of perched birds
## on the wire, or flying birds crossing mid-air. Perched kinds need wire; flying works anywhere.
func _spawn_birds(c: Node2D, i: int, x0: float) -> void:
	if i < safe_spans:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(i, seed_value))
	if is_frenzy(i):
		var x := x0 + 60.0 + rng.randf_range(0.0, 30.0)
		while x < x0 + span - 60.0:
			if rng.randf() < 0.92:
				_add_perched(c, 0, x)
			x += rng.randf_range(frenzy_gap_min, frenzy_gap_max)
		return
	var lane := rng.randi_range(0, lane_count() - 1)
	match _span_birds[i]:
		BirdPattern.SINGLE:
			_add_perched(c, lane, x0 + span * rng.randf_range(0.3, 0.7))
		BirdPattern.LINE:
			_add_line(c, lane, x0, rng, rng.randi_range(2, 4))
		BirdPattern.COMBO:                                         # perched line + a flyer above/ahead of it
			var end := _add_line(c, lane, x0, rng, rng.randi_range(2, 3), 0.45)
			_add_flyer(c, end + rng.randf_range(110.0, 200.0), rng.randf_range(bird_fly_y_min - 30.0, bird_fly_y_min + 20.0),
				-rng.randf_range(bird_fly_speed_min, bird_fly_speed_min + 40.0), rng.randf_range(4.0, 10.0))
		BirdPattern.FLYING:
			var y_lo := bird_fly_y_min
			var y_hi := bird_fly_y_max
			if _span_kind[i] == SpanKind.GAUNTLET:
				y_hi = lane_y[0] - 60.0                            # high, clear of the transformer hops
				y_lo = minf(y_lo, y_hi - 40.0)
			elif not has_wire(i):
				y_lo = bird_fly_y_street                           # low over the street: bounce targets
			var n := 1 if rng.randf() < 0.65 else 2
			var bx := x0 + span * rng.randf_range(0.2, 0.9)
			for k in n:
				_add_flyer(c, bx + k * rng.randf_range(80.0, 140.0), rng.randf_range(y_lo, y_hi),
					-rng.randf_range(bird_fly_speed_min, bird_fly_speed_max), rng.randf_range(4.0, 22.0))
		BirdPattern.WAVE:                                          # diagonal staircase, same speed: slice chain
			var n := rng.randi_range(3, 4)
			var step := 50.0
			var top := rng.randf_range(bird_fly_y_min, bird_fly_y_max - step * (n - 1))
			var rising := rng.randf() < 0.5
			var vx := -rng.randf_range(bird_fly_speed_min, bird_fly_speed_max)
			var bx := x0 + span * rng.randf_range(0.15, 0.5)
			for k in n:
				var y := top + step * ((n - 1 - k) if rising else k)
				_add_flyer(c, bx + k * 110.0, y, vx, 6.0)
		BirdPattern.BRIDGE:                                        # slow low flyer mid-gap to bounce across
			_add_flyer(c, x0 + span * rng.randf_range(0.45, 0.6), rng.randf_range(bird_fly_y_street, bird_fly_y_street + 80.0),
				-rng.randf_range(30.0, 60.0), rng.randf_range(4.0, 8.0))


## 2-4 perched birds lined up on the wire; returns the x of the last one.
func _add_line(c: Node2D, lane: int, x0: float, rng: RandomNumberGenerator, n: int, max_t: float = 1.0) -> float:
	var gap := rng.randf_range(bird_line_gap_min, bird_line_gap_max)
	var extent := gap * (n - 1)
	var hi := maxf(70.0, span * max_t - 70.0 - extent)
	var start := x0 + rng.randf_range(70.0, hi)
	for k in n:
		_add_perched(c, lane, start + gap * k)
	return start + extent


func _add_flyer(c: Node2D, x: float, y: float, vx: float, bob: float) -> void:
	var bird := Bird.new()
	bird.flying = true
	bird.vx = vx
	bird.base_y = y
	bird.bob_amp = bob
	bird.position = Vector2(x, y)
	c.add_child(bird)


func _add_perched(c: Node2D, lane: int, bx: float) -> void:
	var bird := Bird.new()
	bird.position = Vector2(bx, wire_y_at(lane, bx))
	c.add_child(bird)


## Pole post + crossarm + the hop-over obstacle. Pure visual, rect comes from pole_rect_near.
class Pole extends Node2D:
	var top_y := 250.0
	var bottom_y := 620.0
	var lane_ys: Array[float] = []
	var obstacle := true

	const OUTLINE := Color(0.07, 0.06, 0.06)
	const WOOD := Color(0.4, 0.29, 0.2)
	const WOOD_DARK := Color(0.27, 0.19, 0.13)
	const WOOD_LIGHT := Color(0.52, 0.39, 0.27)

	func _ready() -> void:
		if obstacle:                               # the transformer hums: an audible hazard cue
			Sound.emitter(self, "transformer_hum", -9.0, Vector2(0, top_y - 17.0), 1000.0)

	## Wooden pole (grain + shading), crossarm with insulators per wire, and a pole-top transformer that is
	## the hop-over obstacle (same box as pole_rect_near: x -16..16, top_y-34..top_y).
	func _draw() -> void:
		var top := top_y - 40.0
		draw_rect(Rect2(-8, top, 16, bottom_y - top), OUTLINE)
		draw_rect(Rect2(-6, top + 2, 12, bottom_y - top - 2), WOOD)
		draw_rect(Rect2(2, top + 2, 4, bottom_y - top - 2), WOOD_DARK)
		draw_rect(Rect2(-6, top + 2, 2, bottom_y - top - 2), WOOD_LIGHT)
		var y := top + 30.0
		var k := 0
		while y < bottom_y - 10.0:                                   # grain ticks
			draw_rect(Rect2(-2 + (k % 3) * 2, y, 2, 8), WOOD_DARK)
			y += 26.0 + PixelArt.snap((k * 7) % 11)
			k += 1
		draw_rect(Rect2(-10, bottom_y - 14, 20, 14), OUTLINE)        # base sleeve
		draw_rect(Rect2(-8, bottom_y - 12, 16, 12), Color(0.3, 0.3, 0.32))
		draw_rect(Rect2(-8, top_y + 50, 16, 6), Color(0.85, 0.75, 0.3))   # pole tag
		for ly in lane_ys:
			draw_rect(Rect2(-36, ly + 2, 72, 10), OUTLINE)           # crossarm just under the wire
			draw_rect(Rect2(-34, ly + 4, 68, 6), WOOD)
			draw_rect(Rect2(-34, ly + 8, 68, 2), WOOD_DARK)
			PixelArt.line(self, Vector2(-30, ly + 12), Vector2(-8, ly + 34), OUTLINE, 4.0)  # braces
			PixelArt.line(self, Vector2(28, ly + 12), Vector2(6, ly + 34), OUTLINE, 4.0)
			for ix in [-28, 28]:                                     # side insulators
				draw_rect(Rect2(ix - 4, ly - 8, 8, 12), OUTLINE)
				draw_rect(Rect2(ix - 2, ly - 6, 4, 4), Color(0.55, 0.78, 0.72))
				draw_rect(Rect2(ix - 2, ly - 2, 4, 4), Color(0.42, 0.62, 0.58))
		if not obstacle:
			return
		# transformer can (the obstacle) with a hazard band so it reads as "hop me"
		var r := Rect2(-16, top_y - 34, 32, 34)
		draw_rect(r.grow(2.0), OUTLINE)
		draw_rect(r, Color(0.52, 0.56, 0.58))
		draw_rect(Rect2(r.position.x + 24, r.position.y, 8, r.size.y), Color(0.38, 0.41, 0.44))
		draw_rect(Rect2(r.position.x, r.position.y, 32, 4), Color(0.68, 0.72, 0.74))
		for rx in [6, 12, 18]:                                       # cooling ribs
			draw_rect(Rect2(r.position.x + rx, r.position.y + 14, 2, 18), Color(0.4, 0.43, 0.46))
		for hx in 4:
			draw_rect(Rect2(r.position.x + hx * 8, r.position.y + 6, 4, 4), Color(0.95, 0.62, 0.12))
			draw_rect(Rect2(r.position.x + hx * 8 + 4, r.position.y + 6, 4, 4), Color(0.1, 0.1, 0.1))
		for bx in [-8, 8]:                                           # bushings on the lid
			draw_rect(Rect2(bx - 4, r.position.y - 10, 8, 10), OUTLINE)
			draw_rect(Rect2(bx - 2, r.position.y - 8, 4, 6), Color(0.6, 0.45, 0.35))

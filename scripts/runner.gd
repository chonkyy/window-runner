class_name Runner
extends Node2D
## Box ninja. position = feet. Runs on a wire lane (lane >= 0), the street (LANE_STREET) or a car roof (LANE_CAR).
## Driven by Game via step(); no physics engine, wire height is sampled from WireGenerator.

signal hit(reason: String)
signal bird_sliced(pos: Vector2)
signal hopped(combo: int, mult: float, target: Node2D)   ## landed on / bounced off a target; mult = its bonus

# --- tunables ---
@export var gravity := 2400.0
@export var jump_velocity := 900.0
@export var air_jumps := 1                ## extra jumps in mid-air (double jump)
@export var air_jump_velocity := 1000.0   ## second jump; two jumps from the street reach the wire
@export var bounce_velocity := 800.0     ## bounce off a person/bird head
@export var bounce_boost_velocity := 1050.0  ## ...with jump held
@export var jump_cut := 2.6               ## gravity multiplier when jump released early
@export var fall_mult := 1.15
@export var coyote_time := 0.10
@export var buffer_time := 0.12
@export var momentum := 900.0             ## slope -> speed bonus (px/s per unit slope)
@export var screen_target := 320.0        ## preferred x offset from camera left
@export var screen_pull := 1.6
@export var slice_time := 0.10            ## hitbox active window (starts on the press frame)
@export var slice_cooldown := 0.10        ## before the next swing can start
@export var slice_buffer := 0.15          ## presses during cooldown are queued, so mashing never drops a swing
@export var slice_reach := 130.0          ## forward reach; also covers a bit behind the runner

const SIZE := Vector2(26, 48)
const LANE_STREET := -1
const LANE_CAR := -2
## Slice moves (visual only; the hitbox is always slice_rect). On the ground quick presses chain
## DOWN -> UP -> THRUST (lunge finisher); in the air it's a forward SPIN, or a DIVE cleave when falling.
enum Move { DOWN, UP, THRUST, SPIN, DIVE }
const MOVE_LEN := [0.16, 0.16, 0.15, 0.26, 0.22]   ## animation length per Move
const CHAIN_WINDOW := 0.45                ## ground swings closer than this continue the combo string
const CUT_TIME := 0.28                    ## slash line left through a sliced bird
const FLIP_TIME := 0.42                   ## front flip on a bounce or double jump (visual only)
const PERCH_MARGIN := 9.0                  ## horizontal slack for landing on / staying on a target (>= half body width)
const CAR_LAND_TOLERANCE := 10.0          ## feet may be this far below a roof top and still land

static var immortal := false              ## set by Game `--bench`: hits are ignored
var gen: WireGenerator
var lane := 0
var grounded := true
var vy := 0.0
var speed := 0.0
var _air_jumps_left := 0
var combo := 0                            ## consecutive car hops without touching street/wire
var dead := false

var _coyote := 0.0
var _buffer := 0.0
var _ignore_lane := -1
var _slice_t := 0.0
var _slice_cd := 0.0
var _slice_buf := 0.0
var _slice_vis := 0.0                     ## swing animation time left
var _move := Move.DOWN
var _move_len := 0.16
var _chain := 0                           ## swings in the current ground combo string
var _since_swing := 99.0
var _flip := 0.0                          ## front flip time left; cut short on landing
var _chest_pivot := false                 ## this frame's body rotates around the chest (flips)
var _cuts: Array = []                     ## [world pos, angle, age] slash lines through sliced birds
var _no_cut := false                     ## bounce arcs ignore the jump-release cut
var _perch: Node2D = null                 ## car/person we stand on / last stood on (see _hop_targets)

# --- animation only (never read by physics) ---
var _anim_t := 0.0
var _run_dist := 0.0                      ## distance run on the ground, drives the leg cycle
var _foot := false                        ## alternates left/right footstep pitch
var _squash := 0.0                        ## 1 on landing, decays
var _stretch := 0.0                       ## 1 on takeoff, decays
var _dead_t := 0.0
var _rim := false
var _hand := Vector2.ZERO                 ## this frame's sword hand (dash or upright pose)
var _arc_c := Vector2.ZERO                ## this frame's ground slash arc centre

# --- death animation ---
var death_reason := ""
var _dvel := Vector2.ZERO
var _dspin := 0.0
var _drot := 0.0
var _bounces := 0
var _rest := false
var _zap_t := 0.0
var _zap_at := Vector2.ZERO
const ZAP_TIME := 0.6

const DASH_FRAME_PX := 18.0               ## ground distance per dash (run) frame


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rim = TimeOfDay.p().rim


func _process(delta: float) -> void:
	if dead:
		_death_step(delta)
		queue_redraw()


func body_rect() -> Rect2:
	return Rect2(position - Vector2(SIZE.x / 2.0, SIZE.y), SIZE)


func slice_rect() -> Rect2:
	return Rect2(position + Vector2(-14, -76), Vector2(slice_reach + 14.0, 104))


func step(delta: float, scroll_speed: float, cam_left: float) -> void:
	if dead:
		return
	var prev := position
	_tick_timers(delta)
	if Input.is_action_just_pressed("jump"):
		_buffer = buffer_time

	# --- horizontal ---
	var bonus := 0.0
	if grounded and lane >= 0:
		bonus = gen.slope_at(lane, position.x) * momentum
	speed = scroll_speed + bonus
	position.x += speed * delta
	position.x += (cam_left + screen_target - position.x) * screen_pull * delta
	position.x = clampf(position.x, cam_left + 80.0, cam_left + 700.0)

	# --- vertical ---
	if grounded:
		if lane >= 0 and not gen.has_wire_at(position.x):
			_fall_off()                    # wire ended under us -> street below
		elif lane == LANE_CAR and not _on_car_roof():
			_fall_off()                    # slid off the end of the roof
	if grounded:
		_flip = 0.0
		_coyote = coyote_time
		_air_jumps_left = air_jumps
		if lane == LANE_CAR:
			position.y = _perch.roof_y()
		else:
			position.y = gen.floor_y if lane < 0 else gen.wire_y_at(lane, position.x)
		if Input.is_action_just_pressed("drop") and lane >= 0:
			_ignore_lane = lane
			lane = LANE_STREET
			grounded = false
			vy = 150.0
			Sound.play("drop", 1.0, -6.0)
	if _buffer > 0.0 and (grounded or _coyote > 0.0):
		_jump()
	elif _buffer > 0.0 and _air_jumps_left > 0:
		_air_jump()
	if not grounded:
		var g := gravity
		if vy >= 0.0:
			_no_cut = false
		if vy < 0.0 and not Input.is_action_pressed("jump") and not _no_cut:
			g *= jump_cut
		elif vy > 0.0:
			g *= fall_mult
		vy += g * delta
		position.y += vy * delta
		if _ignore_lane >= 0 and position.y > gen.wire_y_at(_ignore_lane, position.x) + 24.0:
			_ignore_lane = -1
		if vy >= 0.0:
			_try_land(prev)

	_check_pole()
	_handle_slice()
	_check_hazards()
	_anim_t += delta
	if grounded:
		var stride := DASH_FRAME_PX * 4.0               # a foot lands every 4 dash frames
		if floori((_run_dist + speed * delta) / stride) != floori(_run_dist / stride):
			_footstep()
		_run_dist += speed * delta
	_squash = maxf(_squash - delta * 7.0, 0.0)
	_stretch = maxf(_stretch - delta * 6.0, 0.0)
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_coyote = maxf(_coyote - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	_slice_t = maxf(_slice_t - delta, 0.0)
	_slice_cd = maxf(_slice_cd - delta, 0.0)
	_slice_buf = maxf(_slice_buf - delta, 0.0)
	_slice_vis = maxf(_slice_vis - delta, 0.0)
	_flip = maxf(_flip - delta, 0.0)
	_since_swing += delta
	for c in _cuts:
		c[2] += delta
	_cuts = _cuts.filter(func(c: Array) -> bool: return c[2] < CUT_TIME)


## Scratchy footfall on whatever we run on; left/right feet pitched apart, wide jitter so no two match.
func _footstep() -> void:
	_foot = not _foot
	var p := 1.0 if _foot else 0.9
	if lane >= 0:
		Sound.play("step_wire", p, -14.0, 0.0, 0.14)
	elif lane == LANE_CAR:
		Sound.play("step_roof", p, -12.0, 0.0, 0.14)
	else:
		Sound.play("step_street", p, -10.0, 0.0, 0.14)


func _fall_off() -> void:
	grounded = false
	lane = LANE_STREET
	vy = 0.0


func _on_car_roof() -> bool:
	return is_instance_valid(_perch) and position.x >= _perch.x_min() - PERCH_MARGIN \
		and position.x <= _perch.x_max() + PERCH_MARGIN


func _air_jump() -> void:
	_air_jumps_left -= 1
	vy = -air_jump_velocity
	_buffer = 0.0
	_ignore_lane = -1
	_stretch = 1.0
	_flip = FLIP_TIME
	Sound.play("double_jump", 1.0, -4.0)


func _jump() -> void:
	vy = -jump_velocity
	if lane == LANE_CAR:
		lane = LANE_STREET
	grounded = false
	_coyote = 0.0
	_buffer = 0.0
	_ignore_lane = -1
	_stretch = 1.0
	Sound.play("jump", 1.0, -4.0)


func _try_land(prev: Vector2) -> void:
	for l in gen.lane_count():
		if l == _ignore_lane:
			continue
		var was := gen.wire_y_at(l, prev.x)
		var now := gen.wire_y_at(l, position.x)
		if gen.has_wire_at(position.x) and prev.y <= was + 1.0 and position.y >= now:
			_land(l)
			return
	for t in _hop_targets():
		var top: float = t.roof_y()
		if prev.y <= top + CAR_LAND_TOLERANCE and position.y >= top \
				and position.x >= t.x_min() - PERCH_MARGIN and position.x <= t.x_max() + PERCH_MARGIN:
			if t.bounces:
				_bounce_off(t)
			else:
				_land_on(t)
			return
	if position.y >= gen.floor_y:
		_land(LANE_STREET)


func _land(l: int) -> void:
	lane = l
	grounded = true
	vy = 0.0
	combo = 0
	_perch = null
	position.y = gen.floor_y if l < 0 else gen.wire_y_at(l, position.x)
	_squash = 1.0
	if l >= 0:                                    # the wire twangs lower mid-span, where it sags most
		var sag := clampf((position.y - gen.lane_y[l]) / gen.sag, 0.0, 1.0)
		Sound.play("wire_land", 1.2 - 0.35 * sag, -3.0)
	else:
		Sound.play("land_street", 1.0, -5.0)


func _land_on(t: Node2D) -> void:
	lane = LANE_CAR
	grounded = true
	vy = 0.0
	position.y = t.roof_y()
	_squash = 1.0
	Sound.play("roof_land", 1.0 if float(t.get("height")) <= 60.0 else 0.72, -3.0)   # bus/truck roofs boom lower
	if t.has_method("hazard"):
		t.hazard()                        # every landing (re)starts the car's hazard blinkers
	if t != _perch:                       # re-landing on the same target doesn't extend the chain
		combo += 1
		hopped.emit(combo, t.hop_mult, t)
	_perch = t


## Stomp a person or bird: bounce straight back up (no standing), refresh the double jump, extend the
## combo. Birds die when stomped; people carry on.
func _bounce_off(t: Node2D) -> void:
	position.y = t.roof_y()
	vy = -(bounce_boost_velocity if Input.is_action_pressed("jump") else bounce_velocity)
	_no_cut = true
	grounded = false
	_air_jumps_left = air_jumps
	_stretch = 1.0
	_flip = FLIP_TIME
	_ignore_lane = -1
	Sound.play("bounce", 1.0, -4.0)
	if t != _perch:
		combo += 1
		hopped.emit(combo, t.hop_mult, t)
	_perch = t
	if t is Bird:
		(t as Bird).slice()
	elif t.has_method("bounced"):
		t.bounced()


## Everything you can land on: cars (stand), people, birds and street lamps (bounce). Each exposes
## roof_y/x_min/x_max/hop_mult/bounces.
func _hop_targets() -> Array:
	return get_tree().get_nodes_in_group("cars") + get_tree().get_nodes_in_group("peds") \
		+ get_tree().get_nodes_in_group("birds") + get_tree().get_nodes_in_group("lamps")


## Touching a pole-top transformer electrocutes.
func _check_pole() -> void:
	if lane == LANE_CAR:
		return                                    # riding a roof: only birds can stop you
	var box := gen.pole_rect_near(position.x)
	if box.has_area() and body_rect().intersects(box):
		_die("electrocuted", null, box.get_center())


func _handle_slice() -> void:
	if Input.is_action_just_pressed("slice"):
		_slice_buf = slice_buffer
	if _slice_buf > 0.0 and _slice_cd <= 0.0:        # fires on the press frame, or as soon as ready
		_slice_buf = 0.0
		_slice_t = slice_time
		_slice_cd = slice_time + slice_cooldown
		_chain = _chain + 1 if _since_swing < CHAIN_WINDOW else 0
		_flip = 0.0                                  # a swing breaks out of the front flip
		_since_swing = 0.0
		if not grounded:
			_move = Move.DIVE if vy > 350.0 else Move.SPIN
		else:
			_move = [Move.DOWN, Move.UP, Move.THRUST][_chain % 3]
		_move_len = MOVE_LEN[_move]
		_slice_vis = _move_len
		match _move:                                 # swish per move
			Move.SPIN:
				Sound.play("slash_spin", 1.0, -5.0)
			Move.DIVE:
				Sound.play("slash", 0.8, -4.0)
			Move.THRUST:
				Sound.play("slash", 0.9, -3.0)
			Move.UP:
				Sound.play("slash", 1.12, -5.0)
			_:
				Sound.play("slash", 1.0, -5.0)
	if _slice_t > 0.0:
		var sr := slice_rect()
		for b in get_tree().get_nodes_in_group("birds"):
			var bird := b as Bird
			if bird.alive and sr.intersects(bird.rect()):
				bird.slice()
				var cut := 0.12 if _move == Move.THRUST else _sweep_angle(_sweep_u()[0]) + PI / 2.0
				_cuts.append([bird.global_position, cut, 0.0])
				bird_sliced.emit(bird.global_position)


## Slice animation progress 0 -> 1.
func _slice_p() -> float:
	return 1.0 - _slice_vis / _move_len


## [head, tail] sweep progress of the blade: the tip sweeps fast, the trail lingers behind it.
func _sweep_u() -> Array:
	var p := _slice_p()
	match _move:
		Move.SPIN:
			var h := 1.0 - pow(1.0 - minf(p * 1.3, 1.0), 2.0)
			return [h, maxf(h - 0.7, 0.0) if p < 0.75 else h - 0.7 * (1.0 - (p - 0.75) / 0.25)]
		Move.DIVE:
			return [minf(p * 1.8, 1.0), maxf(p * 1.8 - 0.8, 0.0)]
	return [minf(p * 2.2, 1.0), maxf(p * 2.2 - 0.7, 0.0)]


## Blade angle (radians, 0 = forward, +y down) at sweep progress u.
func _sweep_angle(u: float) -> float:
	match _move:
		Move.DOWN:
			return lerpf(deg_to_rad(-80.0), deg_to_rad(40.0), u)
		Move.UP:
			return lerpf(deg_to_rad(40.0), deg_to_rad(-80.0), u)
		Move.SPIN:
			return TAU * u
		Move.DIVE:
			return lerpf(deg_to_rad(-160.0), deg_to_rad(70.0), u)
	return 0.0


func _check_hazards() -> void:
	var br := body_rect().grow(-4.0)
	for b in get_tree().get_nodes_in_group("birds"):
		var bird := b as Bird
		if bird.alive and br.intersects(bird.rect()):
			_die("bird", bird)
			return
	if lane == LANE_CAR:
		return                                    # riding a roof: other cars and people can't hurt you
	for c in get_tree().get_nodes_in_group("cars"):
		if br.intersects((c as Car).rect()):
			if br.intersects((c as Car).rear_rect()):
				(c as Car).knock_trunk()           # crashed into its back: the trunk pops open
			_die("car", c)
			return
	for p in get_tree().get_nodes_in_group("peds"):
		if br.intersects((p as Pedestrian).rect()):
			_die((p as Pedestrian).reason_name, p)
			return


## End the run. `other` is what we hit (car/person/bird), `zap_at` the transformer centre. Starts the
## per-cause death animation (run by _process, never by step): the runner keeps its world x unless flung,
## so the still-scrolling camera leaves it behind.
func _die(reason: String, other: Node2D = null, zap_at := Vector2.ZERO) -> void:
	if immortal:                                      # benchmark runs never end (Game `--bench`)
		return
	dead = true
	combo = 0
	death_reason = reason
	speed = 0.0
	_dead_t = 0.0
	_drot = rotation
	match reason:
		"car":                                        # flung up and back, spinning
			_dvel = Vector2(-350.0, -650.0)
			_dspin = -9.0
			Sound.play("crash", 1.0, 0.0)
			if other is Car:
				(other as Car).honk(2, 0.25)          # that vehicle's own horn, furious
				(other as Car).hazard(false)          # and the blinkers go on (no second honk)
		"bird":                                       # bird bursts, runner tumbles off
			_dvel = Vector2(-60.0, -260.0)
			_dspin = -5.0
			Sound.play("squawk", 1.0, -2.0)
			if other is Bird:
				(other as Bird).slice()
		"electrocuted":                               # frozen and fried first, then drops
			_zap_t = ZAP_TIME
			_zap_at = zap_at
			Sound.play("zap", 1.0, -1.0, 0.0, 0.0)
		_:                                            # a person: both go down
			_dvel = Vector2(-120.0, -380.0)
			_dspin = -6.0
			Sound.play("thud", 1.0, -1.0)
			match reason:
				"cyclist":
					Sound.play("bell", 1.0, -5.0, 0.08)
				"motorcyclist":
					Sound.play("moto_rev", 1.0, -3.0, 0.05)
			if other is Pedestrian:
				(other as Pedestrian).cry()           # "Ow!"
				(other as Pedestrian).knock_over(1.0)
			else:
				Sound.play("oof", 1.0, -4.0, 0.04, 0.08)
	queue_redraw()
	hit.emit(reason)


func _death_step(delta: float) -> void:
	_dead_t += delta
	if _zap_t > 0.0:
		_zap_t -= delta
		if _zap_t <= 0.0:
			_dvel = Vector2(-40.0, -200.0)
			_dspin = -4.0
		return
	if _rest:
		_dvel.x = move_toward(_dvel.x, 0.0, 900.0 * delta)          # slide to a stop
		_drot = lerp_angle(_drot, -PI / 2.0, minf(12.0 * delta, 1.0))
		position.x += _dvel.x * delta
		return
	_dvel.y += gravity * delta
	position += _dvel * delta
	_drot += _dspin * delta
	if position.y >= gen.floor_y and _dvel.y > 0.0:
		position.y = gen.floor_y
		if _dvel.y > 300.0 and _bounces < 1:
			_bounces += 1
			_dvel = Vector2(_dvel.x * 0.5, -_dvel.y * 0.35)
			_dspin *= 0.5
			Sound.play("body_thud", 1.0, -4.0)
		else:
			_rest = true
			Sound.play("body_thud", 0.85, -9.0)


func _death_modulate() -> Color:
	if death_reason == "electrocuted":
		if _zap_t > 0.0:
			return Color(3.0, 3.2, 4.0) if int(_dead_t * 24.0) % 2 == 0 else Color(0.2, 0.2, 0.3)
		return Color(0.35, 0.3, 0.3)                                # charred
	return Color(1.0, 0.75, 0.75)


## Sparks and an arc to the transformer while zapping, smoke afterwards. Unrotated local space.
func _draw_zap() -> void:
	if death_reason != "electrocuted":
		return
	var chest := Vector2(0, -28)
	if _zap_t > 0.0:
		var to := _zap_at - position
		var pts := PackedVector2Array([chest])
		for k in range(1, 6):
			pts.append(chest.lerp(to, k / 6.0) + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
		pts.append(to)
		draw_polyline(pts, Color(1.5, 1.8, 3.0), 3.0)
		draw_polyline(pts, Color(3.0, 3.0, 3.0), 1.0)
		for k in 6:
			var d := Vector2.from_angle(randf() * TAU)
			var a := chest + d * randf_range(8, 22)
			draw_line(a, a + d * randf_range(6, 14), Color(2.5, 2.4, 1.2), 2.0)
	else:
		var t := _dead_t - ZAP_TIME
		if t < 1.4:
			for k in 4:
				var p := Vector2(sin(k * 2.1 + t * 3.0) * 6.0, -20.0 - t * 50.0 - k * 10.0)
				draw_circle(p, 5.0 + t * 8.0 + k * 2.0, Color(0.35, 0.35, 0.38, 0.5 * (1.0 - t / 1.4)))


## Picks a NinjaArt frame from the physics state, then draws scarf, (rim), body and slice effects.
## Art pivots on the feet so squash/stretch and lean never move the hitbox.
func _draw() -> void:
	var slicing := _slice_vis > 0.0 and not dead
	var sp := _slice_p() if slicing else 0.0
	var flipping := _flip > 0.0 and not dead and not grounded and not (slicing and _move == Move.SPIN)
	var fp := 1.0 - _flip / FLIP_TIME
	var balled := flipping and fp >= 0.12 and fp < 0.82   # tuck in -> ball -> open out
	var legs := "stand"
	if dead:
		legs = "fall"
	elif flipping:
		legs = "tuck" if fp < 0.12 else "fall"
	elif not grounded:
		legs = "tuck" if vy < 150.0 else "fall"
	var dashing := grounded and not dead and not flipping     # the ground run: forward-leaning dash
	if dashing:
		legs = NinjaArt.DASH[int(_run_dist / DASH_FRAME_PX) % NinjaArt.DASH.size()]
	var bob := Vector2(0, NinjaArt.dash_bob(legs)) if dashing else Vector2.ZERO   # anchors follow the stride bob
	_hand = NinjaArt.DASH_HAND + bob if dashing else NinjaArt.HAND
	_arc_c = NinjaArt.DASH_CHEST + bob if dashing else Vector2(6, -26)

	var sx := 1.0 + 0.14 * _squash - 0.1 * _stretch
	var sy := 1.0 - 0.18 * _squash + 0.16 * _stretch
	var rot := 0.0
	if dead:
		rot = _drot
		sx = 1.0
		sy = 1.0
	elif grounded:
		rot = gen.slope_at(lane, position.x) * 0.5 if lane >= 0 else 0.0   # the dash art leans; follow the wire
	else:
		rot = clampf(vy / 4000.0, -0.15, 0.2)
	var snap_off := position.round() - position     # keep art pixels on screen pixels
	var lunge := Vector2.ZERO
	if flipping:                                       # tucked front flip around the chest
		rot += TAU * (1.0 - pow(1.0 - fp, 2.2))
		sx = lerpf(sx, 1.0, 0.7)
		sy = lerpf(sy, 1.0, 0.7)
	_chest_pivot = not dead and (flipping or (slicing and _move == Move.SPIN))
	if slicing:
		match _move:
			Move.SPIN:                                     # forward flip around the chest
				rot = _sweep_angle(_sweep_u()[0])
				sx = 1.0
				sy = 1.0
			Move.DIVE:                                     # pitch into the cleave
				rot += 0.45 * sin(sp * PI)
			Move.THRUST:                                   # lunge forward and low, then recover
				lunge = Vector2(14.0, 3.0) * sin(minf(sp * 1.6, 1.0) * PI)
				sx *= 1.0 + 0.12 * sin(minf(sp * 1.6, 1.0) * PI)
	var rect := Rect2(-NinjaArt.W, -NinjaArt.H * NinjaArt.SCALE, NinjaArt.W * NinjaArt.SCALE, NinjaArt.H * NinjaArt.SCALE)
	if balled:
		rect = NinjaArt.BALL_RECT
	elif dashing:
		rect = NinjaArt.DASH_RECT
	if slicing and _move != Move.DOWN and _move != Move.UP:   # afterimages
		var ghost := _body_tex(legs, balled, dashing, true, true)
		for g: int in [3, 2, 1]:
			var grot := rot - 0.55 * g if _move == Move.SPIN else rot
			_body_transform(snap_off + lunge * (1.0 - 0.3 * g) + Vector2(-9.0 * g, 0), grot, Vector2(sx, sy))
			draw_texture_rect(ghost, rect, false, Color(0.5, 1.1, 1.8, 0.32 * (1.0 - sp) * (1.0 - 0.22 * g)))
	elif flipping and fp < 0.8:                                 # faint motion blur behind the flip
		var ghost := _body_tex(legs, balled, dashing, slicing, true)
		for g: int in [2, 1]:
			_body_transform(snap_off, rot - 0.6 * g, Vector2(sx, sy))
			draw_texture_rect(ghost, rect, false, Color(0.9, 0.95, 1.3, 0.18 * (1.0 - fp / 0.8) * (1.0 - 0.3 * g)))
	_body_transform(snap_off + lunge, rot, Vector2(sx, sy))

	_draw_scarf(NinjaArt.BALL_NECK if balled else (NinjaArt.DASH_NECK + bob if dashing else NinjaArt.NECK))
	if _rim:
		var sil := _body_tex(legs, balled, dashing, slicing, true)
		var rim_col := Color(1.8, 2.1, 2.8, 0.85)                  # >1 so it survives the night tint
		draw_texture_rect(sil, Rect2(rect.position + Vector2(-2, -2), rect.size), false, rim_col)
	var mod := Color.WHITE
	if dead:
		mod = _death_modulate()
	draw_texture_rect(_body_tex(legs, balled, dashing, slicing, false), rect, false, mod)
	var tip := Vector2.ZERO
	if slicing:
		var u: Array = _sweep_u()
		var a := 0.0 if _move == Move.SPIN else _sweep_angle(u[0]) - rot   # blade in body space
		tip = _hand + Vector2.from_angle(a) * (40.0 if _move == Move.THRUST else 34.0)
		draw_line(_hand, tip, Color(0.06, 0.06, 0.09), 4.0)
		draw_line(_hand, tip, Color(0.88, 0.93, 1.0), 2.0)
		tip = _body_xform(snap_off + lunge, rot, Vector2(sx, sy)) * tip
	draw_set_transform(snap_off)
	if dead:
		_draw_zap()
		return
	if slicing:
		_draw_slash(sp, tip - snap_off, lunge)
	_draw_cuts()


func _body_tex(legs: String, balled: bool, dashing: bool, slicing: bool, sil: bool) -> ImageTexture:
	if balled:
		return NinjaArt.ball(sil)
	return NinjaArt.dash_frame(legs, slicing, sil) if dashing else NinjaArt.frame(legs, slicing, sil)


## Body draw transform: rotation/scale pivot on the feet, except flips (front flip, SPIN) pivot on the chest.
func _body_xform(off: Vector2, rot: float, sc: Vector2) -> Transform2D:
	var pivot := Vector2(0, -26) if _chest_pivot else Vector2.ZERO
	var t := Transform2D(rot, sc, 0.0, Vector2.ZERO)
	return Transform2D(rot, sc, 0.0, off + pivot - t * pivot)


func _body_transform(off: Vector2, rot: float, sc: Vector2) -> void:
	draw_set_transform_matrix(_body_xform(off, rot, sc))


## Swing trail for the current move (local space, unrotated) plus a gleam on the blade tip.
func _draw_slash(p: float, tip: Vector2, lunge: Vector2) -> void:
	var fade := 1.0 - p * 0.8
	if _move == Move.THRUST:                                   # stab streak + speed lines
		var e := minf(p * 2.6, 1.0)
		var base := _hand + lunge
		var end := base + Vector2(slice_reach * 0.95 * e, 0)
		var a := fade
		draw_colored_polygon(PackedVector2Array([base + Vector2(0, -7), end, base + Vector2(0, 7)]), Color(0.6, 1.0, 1.8, 0.45 * a))
		draw_colored_polygon(PackedVector2Array([base + Vector2(0, -3), end, base + Vector2(0, 3)]), Color(2.2, 2.3, 2.4, 0.9 * a))
		for k: int in [-1, 1]:
			var y := base.y + k * 14.0
			draw_line(Vector2(base.x - 10.0 + 30.0 * e, y), Vector2(base.x + 30.0 + 50.0 * e, y), Color(1.4, 1.8, 2.2, 0.6 * a), 2.0)
	else:
		var u: Array = _sweep_u()
		var c := _arc_c
		var r := slice_reach * 0.62
		var w := 14.0
		match _move:
			Move.SPIN:
				c = Vector2(0, -26)
				r = 52.0
				w = 16.0
			Move.DIVE:
				c = Vector2(4, -30)
				r = slice_reach * 0.68
				w = 20.0
		var a0 := _sweep_angle(u[1])
		var a1 := _sweep_angle(u[0])
		_crescent(c, r + 5.0, a0, a1, w + 8.0, Color(0.5, 0.95, 1.8, 0.35 * fade))      # glow
		_crescent(c, r, a0, a1, w, Color(2.0, 2.2, 2.4, 0.95 * fade))                   # edge
		if _move == Move.DIVE and u[0] >= 1.0:                                           # impact streaks
			var hit := c + Vector2.from_angle(a1) * r
			for k in 3:
				var d := Vector2.from_angle(a1 + 1.2 + k * 0.5)
				draw_line(hit + d * 6.0, hit + d * (16.0 + 22.0 * p), Color(2.0, 2.0, 1.6, fade), 2.0)
	if p > 0.25 and p < 0.8:                                   # gleam on the blade tip
		var g := sin((p - 0.25) / 0.55 * PI) * 9.0
		var gc := Color(2.6, 2.6, 2.3)
		draw_line(tip - Vector2(g, 0), tip + Vector2(g, 0), gc, 2.0)
		draw_line(tip - Vector2(0, g), tip + Vector2(0, g), gc, 2.0)


## Filled arc band from angle a0 (thin tail) to a1 (thick head), outer radius r.
func _crescent(c: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	if absf(a1 - a0) < 0.02:
		return
	var n := 18
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		var d := Vector2.from_angle(lerpf(a0, a1, k))
		outer.append(c + d * r)
		inner.append(c + d * (r - w * k * k))
	inner.reverse()
	outer.append_array(inner)
	draw_colored_polygon(outer, col)


## Slash lines through freshly sliced birds: shoot out to full length, then thin away.
func _draw_cuts() -> void:
	for cut in _cuts:
		var k: float = cut[2] / CUT_TIME
		var at: Vector2 = cut[0] - position.round()
		var d := Vector2.from_angle(cut[1]) * 46.0 * minf(k * 5.0, 1.0)
		draw_line(at - d, at + d, Color(0.6, 1.1, 1.9, 0.6 * (1.0 - k)), 8.0 * (1.0 - k) + 1.0)
		draw_line(at - d, at + d, Color(2.6, 2.6, 2.6, 1.0 - k), 3.0 * (1.0 - k) + 1.0)


## Two-tone scarf tail trailing from the neck; longer with speed, lifted by falling, waving in the wind.
## The bright red is the design's readability accent for Dusk/Night.
func _draw_scarf(neck: Vector2) -> void:
	var n := 7
	var length := clampf(14.0 + speed * 0.045, 22.0, 56.0)
	var lift := clampf(-vy * 0.012, -10.0, 10.0) if not grounded else 0.0
	var pts: Array[Vector2] = []
	for i in n + 1:
		var k := float(i) / n
		var wave := sin(_anim_t * 15.0 - i * 0.9) * (1.0 + 5.0 * k)
		pts.append(neck + Vector2(-length * k, wave + lift * k * k + 2.0 * k))
	for i in n:
		var w := PixelArt.snap(lerpf(6.0, 4.0, float(i) / n))
		var a := pts[i].snapped(Vector2(2, 2))
		var b := pts[i + 1].snapped(Vector2(2, 2))
		PixelArt.line(self, a + Vector2(0, 2), b + Vector2(0, 2), NinjaArt.PALETTE["r"], w)   # shaded underside
		PixelArt.line(self, a, b, NinjaArt.PALETTE["R"], w - 2.0)

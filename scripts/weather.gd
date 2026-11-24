class_name Weather
extends CanvasLayer
## Rain (purely visual + audio; it only thins out the people on the street, see Traffic). Each round rolls
## dry / light / heavy from the round seed (`roll`, before anything reads it); `-- --rain=0|1|2` forces it.
## Static state so everything can ask (`Weather.rain`, `active()`): Backdrop greys the sky, TimeOfDay.tint()
## darkens the world, Game wets the road reflection, people carry umbrellas, Cabin's window gets droplets.
## The node itself (Game adds one when it rains) is the screen-space rain: slanted streaks between the
## reflection (layer 1) and the HUD (layer 10), splashes on the road and on car roofs, and at Dusk/Night in
## heavy rain the odd lightning flash + thunder.

enum Level { DRY, LIGHT, HEAVY }
const CHANCE := [0.6, 0.25, 0.15]         ## indexed by Level
const AMOUNT := [0.0, 0.4, 1.0]           ## rain 0..1 per level

static var level := Level.DRY
static var rain := 0.0                    ## 0 dry .. 1 heavy
static var force := -1
static var _args_read := false


static func roll(seed_value: int) -> void:
	_read_args()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5bd1e995
	var r := rng.randf()
	level = Level.DRY if r < CHANCE[0] else (Level.LIGHT if r < CHANCE[0] + CHANCE[1] else Level.HEAVY)
	if force >= 0:
		level = clampi(force, 0, 2) as Level
	rain = AMOUNT[level]


static func active() -> bool:
	return rain > 0.0


static func heavy() -> bool:
	return level == Level.HEAVY


static func _read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rain="):
			force = int(a.trim_prefix("--rain="))


# --- screen-space rain (instance) ---

static var VIEW := View.BASE                ## screen size, set in _ready (View.size())
const FALL := Vector2(900.0, 1350.0)      ## streak fall speed range, px/s
const WIND := -70.0                       ## px/s sideways drift on top of the scroll
const STREAKS := [0, 80, 230]             ## per level
const SPLASH_LIFE := 0.16

var floor_y := 620.0
var cam_x := 0.0
var scroll_speed := 0.0
var _fx: RainFx


func _ready() -> void:
	VIEW = View.size()
	layer = 2
	_fx = RainFx.new()
	_fx.owner_w = self
	add_child(_fx)


class RainFx extends Node2D:
	var owner_w: Weather
	var _drops: Array = []                   ## [pos, speed, depth 0 far..1 near, end_y]
	var _splashes: Array = []                ## [pos, age, size]
	var _col := Color.WHITE
	var _flash := 0.0
	var _thunder_t := 0.0
	var _storm := false
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		_rng.randomize()
		if Runner.immortal:                                  # Game `--bench`: repeatable rain
			_rng.seed = 0x2f6b
		var t: Color = TimeOfDay.tint()
		# this layer isn't under the world CanvasModulate: tint by hand, a little brighter so it still reads
		_col = Color(0.8, 0.86, 1.0) * Color(t.r, t.g, t.b).lerp(Color.WHITE, 0.25)
		for i in STREAKS[Weather.level]:
			_drops.append(_new_drop(true))
		_storm = Weather.heavy() and TimeOfDay.lights_on()
		_thunder_t = _rng.randf_range(8.0, 20.0)

	func _new_drop(anywhere: bool) -> Array:
		var depth := _rng.randf()
		var y := _rng.randf_range(-40.0, Weather.VIEW.y) if anywhere else _rng.randf_range(-120.0, -20.0)
		# far drops die somewhere over the backdrop, near ones on the road (splash)
		var end_y := _rng.randf_range(200.0, owner_w.floor_y) if depth < 0.45 \
			else _rng.randf_range(owner_w.floor_y - 6.0, Weather.VIEW.y)
		return [Vector2(_rng.randf_range(-60.0, Weather.VIEW.x + 260.0), y), _rng.randf_range(FALL.x, FALL.y) * (0.75 + 0.25 * depth),
			depth, end_y]

	func _vel(d: Array) -> Vector2:
		var depth: float = d[2]
		# the camera scrolls right, so drops slide left on screen; near drops more (parallax)
		return Vector2(WIND - owner_w.scroll_speed * (0.35 + 0.5 * depth), d[1])

	func _process(delta: float) -> void:
		for d in _drops:
			d[0] += _vel(d) * delta
			if d[0].y >= d[3] or d[0].x < -80.0:
				if d[2] >= 0.45 and d[0].y >= owner_w.floor_y - 8.0 and _rng.randf() < 0.6:
					_splashes.append([Vector2(d[0].x, d[3]).snapped(Vector2(2, 2)), 0.0, 1.0 + d[2]])
				var nd := _new_drop(false)
				d[0] = nd[0]
				d[1] = nd[1]
				d[2] = nd[2]
				d[3] = nd[3]
		# the odd splash on a car roof (cars are world-space, this layer is screen-space)
		if _rng.randf() < delta * 20.0 * Weather.rain:
			var cars := get_tree().get_nodes_in_group("cars")
			if not cars.is_empty():
				var c: Car = cars[_rng.randi() % cars.size()]
				var x := _rng.randf_range(c.x_min(), c.x_max()) - owner_w.cam_x
				if x > 0.0 and x < Weather.VIEW.x:
					_splashes.append([Vector2(x, c.roof_y()).snapped(Vector2(2, 2)), 0.0, 1.4])
		var i := _splashes.size() - 1
		while i >= 0:
			_splashes[i][1] += delta
			_splashes[i][0].x -= owner_w.scroll_speed * delta      # splashes stay put in the world
			if _splashes[i][1] >= SPLASH_LIFE:
				_splashes.remove_at(i)
			i -= 1
		_update_storm(delta)
		queue_redraw()

	## Heavy rain after dark: a faint double flash over everything now and then, thunder rolls in after it.
	func _update_storm(delta: float) -> void:
		_flash = maxf(_flash - delta * 2.2, 0.0)
		if not _storm:
			return
		_thunder_t -= delta
		if _thunder_t > 0.0:
			return
		_thunder_t = _rng.randf_range(25.0, 40.0)
		_flash = 1.0
		var tw := create_tween()
		tw.tween_interval(0.14)
		tw.tween_callback(func() -> void: _flash = 0.7)
		Sound.play("thunder", _rng.randf_range(0.85, 1.1), -4.0, _rng.randf_range(0.5, 1.4), 0.0, "World")

	func _draw() -> void:
		var a0 := 0.16 + 0.12 * Weather.rain
		for d in _drops:
			var depth: float = d[2]
			var v := _vel(d)
			var p: Vector2 = d[0]
			var len := 0.016 + 0.012 * depth
			draw_line(p, p - v * len, Color(_col, a0 * (0.45 + 0.55 * depth)), 2.0 if depth > 0.55 else 1.0)
		for s in _splashes:
			var k: float = s[1] / SPLASH_LIFE
			var p: Vector2 = s[0]
			var w: float = 2.0 * roundf(s[2])
			var up := PixelArt.snap(6.0 * sin(k * PI))
			var spread := PixelArt.snap(2.0 + 6.0 * k)
			var c := Color(_col, 0.55 * (1.0 - k))
			draw_rect(Rect2(p + Vector2(-spread - w, -up), Vector2(w, 2.0)), c)
			draw_rect(Rect2(p + Vector2(spread, -up), Vector2(w, 2.0)), c)
			if k < 0.4:
				draw_rect(Rect2(p + Vector2(-w, -2.0), Vector2(w * 2.0, 2.0)), c)
		if _flash > 0.0 and Settings.flashes:
			draw_rect(Rect2(Vector2.ZERO, Weather.VIEW), Color(0.85, 0.9, 1.0, 0.13 * _flash))

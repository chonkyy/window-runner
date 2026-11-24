class_name Street
extends Node2D
## Far sidewalk, asphalt road strip, lane dashes, decals and street lamps. Everything stands on floor_y;
## the road below it is where WetReflection mirrors the scene. Lamps glow (PointLight2D pool + drawn
## halo/cone) when the time-of-day preset turns them on. At Dusk/Night some lamps are dead or flicker;
## bouncing on one fixes it (lamp_fixed). Every bounce throws sparks (Street.Sparks).

signal lamp_fixed(at: Vector2)             ## a dead/flickering lamp was bounced back to life

var floor_y := 620.0
var cam_x := 0.0

const SIDEWALK_H := 12.0                  ## thin far sidewalk (incl. 4 px curb) above the asphalt
const PED_LIFT := 14.0                    ## people on foot stand this far above floor_y (on the sidewalk)
const DASH := 70.0
const PERIOD := 160.0
const DECAL_CELL := 160.0
const LAMP_SPACING := 640.0
const LAMP_OFFSET := 320.0                ## mid-span, away from the power poles
const LAMP_HEIGHT := 190.0
const LAMP_POOL := 4
const FIX_TIME := 0.9                     ## fixed lamp: stutters on, then flares and settles

const ASPHALT := Color(0.24, 0.25, 0.29)
const ASPHALT_DARK := Color(0.2, 0.21, 0.25)
const SIDEWALK := Color(0.58, 0.56, 0.55)
const SIDEWALK_DARK := Color(0.46, 0.44, 0.44)
const CURB := Color(0.7, 0.69, 0.67)
const OUTLINE := Color(0.08, 0.08, 0.1)
const SODIUM := Color(1.0, 0.72, 0.42)

var _lamp_energy := 0.0
var _phase := 0
var _fixed := {}                          ## lamp k -> _t when it was fixed
var _sparks: Sparks
var _lights: Array[PointLight2D] = []
var _lamps: Array[Lamp] = []
var _t := 0.0
## The static road (sidewalk, asphalt, decals, dashes) is painted in world x over [x, y), well past the
## screen, and only repainted when the view leaves it; the lamps live on their own layer (`_lamp_art`)
## that repaints only when a lamp's look changes.
const PAINT_AHEAD := 1280.0
var _painted := Vector2(INF, -INF)
var _lamp_art: Node2D
var _lamp_key: Array = []


func _ready() -> void:
	var p := TimeOfDay.p()
	_lamp_energy = p.lamps
	_phase = TimeOfDay.phase()
	_lamp_art = LampArt.new()
	_lamp_art.street = self
	add_child(_lamp_art)
	_sparks = Sparks.new()
	_sparks.z_index = 20                        # in front of the runner (Street itself is z -1)
	add_child(_sparks)
	for i in LAMP_POOL:                          # bounce targets, always present (lit or not)
		var lamp := Lamp.new()
		lamp.street = self
		add_child(lamp)
		_lamps.append(lamp)
	_place_lamps()
	if _lamp_energy <= 0.0:
		return
	for lamp in _lamps:                          # flickering lamps buzz (silent until one is in the pool)
		lamp.buzz = Sound.emitter(lamp, "lamp_buzz", -80.0, Vector2(0, 10), 900.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	for i in LAMP_POOL:
		var l := PointLight2D.new()
		l.texture = tex
		l.texture_scale = 2.8
		l.color = SODIUM
		l.energy = _lamp_energy
		add_child(l)
		_lights.append(l)


func _process(delta: float) -> void:
	_t += delta
	_place_lamps()
	for lamp in _lamps:
		lamp.bump = maxf(lamp.bump - delta * 5.0, 0.0)
		if lamp.buzz:
			var flicker := _fault(lamp.k) == 2
			lamp.buzz.volume_db = ((-12.0 if _lamp_level(lamp.k) > 0.5 else -20.0) + Sound.trim_db("lamp_buzz")) \
				if flicker else -80.0
	_place_lights()
	var left := _view_left()
	if left < _painted.x or left + VIEW_W > _painted.y:
		_painted = Vector2(left, left + VIEW_W + PAINT_AHEAD)
		queue_redraw()
	var key := _lamp_state(left)
	if key != _lamp_key:
		_lamp_key = key
		_lamp_art.queue_redraw()


const VIEW_W := 1420.0                    ## painted width around the view (screen + margins)


func _view_left() -> float:
	return floorf((cam_x - 60.0) / 4.0) * 4.0


## Visible lamps' range and look (dip, light level, fault): the lamp layer repaints when this changes.
func _lamp_state(left: float) -> Array:
	var s := []
	var k := int(floorf((left - LAMP_OFFSET - 40.0) / LAMP_SPACING))
	while LAMP_OFFSET + k * LAMP_SPACING < left + VIEW_W + 40.0:
		s.append_array([k, PixelArt.snap(sin(_bump(k) * PI) * 6.0), _lamp_energy * _lamp_level(k), _fault(k)])
		k += 1
	return s


func _lamp_head(k: int) -> Vector2:
	return Vector2(LAMP_OFFSET + k * LAMP_SPACING + 26.0, floor_y - 8.0 - LAMP_HEIGHT)


## 0 = works, 1 = dead, 2 = flickering. Deterministic per lamp; only while lamps are lit (Dusk has
## the most: still warming up). Fixed lamps work for the rest of the round.
func _fault(k: int) -> int:
	if _lamp_energy <= 0.0 or _fixed.has(k):
		return 0
	var h := absi(hash(k * 31 + 7))
	match _phase:
		TimeOfDay.Phase.DUSK:
			return [1, 2, 0, 0, 0][h % 5]
		TimeOfDay.Phase.NIGHT:
			return [1, 2, 0, 0, 0, 0, 0][h % 7]
	return 0


func _lamp_level(k: int) -> float:
	if _fixed.has(k):
		var u: float = _t - _fixed[k]
		if u < FIX_TIME * 0.4:
			return 1.0 if fmod(u * 26.0, 2.0) < 0.9 else 0.1                 # stutters on
		return 1.0 + 0.9 * maxf(1.0 - (u - FIX_TIME * 0.4) / (FIX_TIME * 0.6), 0.0)   # flare, settle
	match _fault(k):
		1:
			return 0.0
		2:
			return 0.25 if fmod(_t * 7.0 + k, 4.0) < 0.6 or fmod(_t * 13.0, 9.0) < 0.4 else 1.0
	return 1.0


## Runner bounced on lamp k: sparks every time; a dead/flickering lamp comes back on.
func _on_lamp_bounced(lamp: Lamp) -> void:
	var bulb := _lamp_head(lamp.k) + Vector2(0, 10)
	Sound.play_at("lamp_clang", bulb, 1.0, -5.0)
	Sound.play_at("spark_crackle", bulb, 1.0, -7.0)
	if _fault(lamp.k) != 0:
		_fixed[lamp.k] = _t
		_sparks.burst(bulb, 26, 1.3)
		lamp_fixed.emit(bulb)
	else:
		_sparks.burst(bulb, 10, 0.8)


## Keep the Lamp target pool on the lamps around the camera (lamp k is fixed in the world).
func _place_lamps() -> void:
	var k0 := int(floorf((cam_x - 200.0 - LAMP_OFFSET) / LAMP_SPACING))
	for i in _lamps.size():
		var k := k0 + i
		if _lamps[i].k != k:
			_lamps[i].k = k
			_lamps[i].bump = 0.0
		_lamps[i].position = _lamp_head(k)


func _bump(k: int) -> float:
	for lamp in _lamps:
		if lamp.k == k:
			return lamp.bump
	return 0.0


func _place_lights() -> void:
	if _lights.is_empty():
		return
	var k0 := int(floorf((cam_x - 200.0 - LAMP_OFFSET) / LAMP_SPACING))
	for i in _lights.size():
		var k := k0 + i
		_lights[i].position = _lamp_head(k) + Vector2(0, 20)
		_lights[i].energy = _lamp_energy * _lamp_level(k)
		_lights[i].visible = _lights[i].energy > 0.0        # dead lamps: no light pass at all


func _draw() -> void:
	var left := _painted.x
	var right := _painted.y
	var top := floor_y - 8.0

	# thin far sidewalk with paving joints; people on foot walk on it (feet at floor_y - PED_LIFT)
	var walk := top - SIDEWALK_H
	draw_rect(Rect2(left, walk, right - left, SIDEWALK_H), SIDEWALK)
	draw_rect(Rect2(left, walk, right - left, 2.0), SIDEWALK_DARK)
	var x := floorf(left / 48.0) * 48.0
	while x < right:
		draw_rect(Rect2(x, walk + 2.0, 2.0, SIDEWALK_H - 6.0), SIDEWALK_DARK)
		x += 48.0
	draw_rect(Rect2(left, top - 4.0, right - left, 4.0), CURB)

	# road: banded asphalt
	draw_rect(Rect2(left, top, right - left, 140.0), ASPHALT)
	draw_rect(Rect2(left, top, right - left, 4.0), OUTLINE)
	for band in [[top + 18.0, 6.0], [top + 40.0, 4.0], [top + 86.0, 8.0]]:
		draw_rect(Rect2(left, band[0], right - left, band[1]), ASPHALT_DARK)

	# decals per cell: manhole, crack, patch (deterministic by world x)
	var c := int(floorf(left / DECAL_CELL))
	while c * DECAL_CELL < right:
		var h := absi(hash(c * 7 + 3))
		var cx := c * DECAL_CELL + float(h % 100)
		match h % 7:
			0:
				draw_rect(Rect2(cx, top + 26.0, 40.0, 6.0), OUTLINE)
				draw_rect(Rect2(cx + 2.0, top + 27.0, 36.0, 4.0), Color(0.32, 0.32, 0.35))
			1, 2:
				draw_line(Vector2(cx, top + 48.0), Vector2(cx + 14.0, top + 52.0), ASPHALT_DARK.darkened(0.2), 2.0)
				draw_line(Vector2(cx + 14.0, top + 52.0), Vector2(cx + 30.0, top + 50.0), ASPHALT_DARK.darkened(0.2), 2.0)
			3:
				draw_rect(Rect2(cx, top + 92.0, 64.0, 10.0), Color(0.27, 0.28, 0.32))
		c += 1

	# lane dashes
	x = floorf(left / PERIOD) * PERIOD
	while x < right:
		draw_rect(Rect2(x, floor_y + 62.0, DASH, 6.0), Color(0.85, 0.82, 0.55))
		draw_rect(Rect2(x, floor_y + 66.0, DASH, 2.0), Color(0.62, 0.6, 0.42))
		x += PERIOD


## Street lamps on the far sidewalk, on their own layer above the road (repainted only on change).
class LampArt extends Node2D:
	var street: Street

	func _draw() -> void:
		var left := street._view_left()
		var top := street.floor_y - 8.0
		var k := int(floorf((left - LAMP_OFFSET - 40.0) / LAMP_SPACING))
		while LAMP_OFFSET + k * LAMP_SPACING < left + VIEW_W + 40.0:
			street._draw_lamp(self, k, top)
			k += 1


func _draw_lamp(ci: CanvasItem, k: int, top: float) -> void:
	var bx := LAMP_OFFSET + k * LAMP_SPACING
	var head := _lamp_head(k) + Vector2(0, PixelArt.snap(sin(_bump(k) * PI) * 6.0))   # dips when bounced on
	var pole_col := Color(0.2, 0.22, 0.26)
	ci.draw_rect(Rect2(bx - 4, head.y, 8, top - head.y), OUTLINE)
	ci.draw_rect(Rect2(bx - 2, head.y + 2, 4, top - head.y - 2), pole_col)
	ci.draw_rect(Rect2(bx - 6, top - 12, 12, 10), OUTLINE)                                 # base
	ci.draw_rect(Rect2(bx - 4, head.y - 2, 34, 6), OUTLINE)                                # arm
	ci.draw_rect(Rect2(bx - 2, head.y, 30, 2), pole_col)
	ci.draw_rect(Rect2(head.x - 10, head.y + 2, 20, 8), OUTLINE)                           # shade
	var lit := _lamp_energy * _lamp_level(k)
	var bulb := Color(0.7, 0.68, 0.6) if lit <= 0.0 else Color(2.5, 2.0, 1.3)
	ci.draw_rect(Rect2(head.x - 8, head.y + 8, 16, 4), bulb)
	if lit <= 0.0:
		if _fault(k) == 1:                                                  # dead: cracked bulb
			ci.draw_rect(Rect2(head.x - 2, head.y + 8, 2, 4), OUTLINE)
			ci.draw_rect(Rect2(head.x + 4, head.y + 10, 2, 2), OUTLINE)
		return
	var a := clampf(lit, 0.0, 2.0)
	# light cone down to the road, then soft halo around the bulb (>1 colours survive the night tint)
	ci.draw_polygon(PackedVector2Array([Vector2(head.x - 8, head.y + 12), Vector2(head.x + 8, head.y + 12),
		Vector2(head.x + 90, floor_y + 4), Vector2(head.x - 90, floor_y + 4)]),
		PackedColorArray([Color(1.8, 1.3, 0.8, 0.22 * a), Color(1.8, 1.3, 0.8, 0.22 * a),
		Color(1.8, 1.3, 0.8, 0.0), Color(1.8, 1.3, 0.8, 0.0)]))
	for r in [10.0, 20.0, 34.0]:
		ci.draw_circle(head + Vector2(0, 10), r, Color(1.8, 1.4, 0.9, 0.16 * a))


## Bounce target on a street lamp head (Runner._hop_targets, group "lamps"). Like people and birds you
## bounce off it (refreshes the double jump, extends the combo); it's never a hazard.
## position = lamp head (arm tip); the landing span covers the arm and shade.
class Lamp extends Node2D:
	var k := -999999
	var bump := 0.0                        ## 1 when bounced on, decays (drawn as a dip)
	var bounces := true
	var street: Street
	var hop_mult := 1.0
	var buzz: AudioStreamPlayer2D            ## flicker buzz (Dusk/Night)

	func _ready() -> void:
		add_to_group("lamps")

	func roof_y() -> float:
		return position.y - 2.0

	func x_min() -> float:
		return position.x - 30.0

	func x_max() -> float:
		return position.x + 10.0

	func bounced() -> void:
		bump = 1.0
		if street:
			street._on_lamp_bounced(self)


## Electric sparks: hot streaks that spray out, arc down under gravity and cool from white to orange.
## World space; colours > 1 survive the night tint.
class Sparks extends Node2D:
	const GRAVITY := 1100.0
	var _p: Array = []                     ## [pos, vel, life, max_life]

	func burst(at: Vector2, n: int, power: float) -> void:
		for i in n:
			var a := randf_range(-PI, 0.0) if randf() < 0.75 else randf_range(0.0, PI)   # mostly upward
			var v := Vector2.from_angle(a) * randf_range(140.0, 420.0) * power
			var life := randf_range(0.3, 0.7)
			_p.append([at + Vector2(randf_range(-6.0, 6.0), 0.0), v, life, life])

	func _process(delta: float) -> void:
		var i := _p.size() - 1
		while i >= 0:
			var s: Array = _p[i]
			s[1].y += GRAVITY * delta
			s[0] += s[1] * delta
			s[2] -= delta
			if s[2] <= 0.0:
				_p.remove_at(i)
			i -= 1
		queue_redraw()

	func _draw() -> void:
		for s in _p:
			var k: float = s[2] / s[3]                                     # 1 fresh .. 0 dead
			var col := Color(2.6, 2.3, 1.6, 1.0).lerp(Color(2.2, 0.9, 0.25, 0.0), 1.0 - k)
			var v: Vector2 = s[1]
			var w := 4.0 if k > 0.5 else 2.0
			draw_line(s[0], s[0] - v * 0.04, col, w)
			draw_rect(Rect2(s[0] - Vector2(w, w) / 2.0, Vector2(w, w)), Color(3.0, 2.8, 2.2, col.a))   # hot head

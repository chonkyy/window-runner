class_name Car
extends Node2D
## Street car. position.x = left edge, position.y = street surface (bottom of the car).
## Side contact kills the runner; landing on the roof (see roof_y) is a car hop.

const HEIGHT := 56.0                       ## default roof height
const VAN_HEIGHT := 68.0
const BUS_HEIGHT := 100.0
const TRUCK_HEIGHT := 108.0                ## trailer roof; the cab's roof fairing reaches the same height

var length := 150.0
var vx := 0.0                              ## world velocity (px/s); negative = oncoming
var color := Color(0.8, 0.2, 0.2)
var bounces := false                       ## cars are stood on, not bounced off
var hop_mult := 1.0                        ## hop score multiplier for landing on this


var _engine: AudioStreamPlayer2D
var _blink_was := false
var _clattered := false
var _horn_pitch := 1.0                     ## every car's horn is a little different
var _honks := 0                            ## landings during this blinker run (escalates the honk)


func _ready() -> void:
	add_to_group("cars")
	var big := model == Model.BUS or model == Model.TRUCK
	_engine = Sound.emitter(self, "engine_big" if big else "engine_car", -7.0 if big else -10.0,
		Vector2(length / 2.0, -20.0), 1500.0)
	_horn_pitch = randf_range(0.96, 1.04)       # global rng: Traffic's spawn sequence stays the same
	for l in Layer.size():                      # drawing layers (body, wheels, junk); see _update_layers
		var c := CarLayer.new()
		c.car = self
		c.layer = l
		add_child(c)
		_layers.append(c)


## Folder name of this vehicle's recorded horn (audio/horns/<name>/).
func horn_name() -> String:
	return String(Model.keys()[model]).to_lower()


## The driver leans on the horn. level 0 = a tap (or "beep beep"), 1 = double, 2 = angry (tap tap HOOONK, or one
## long lean). Taxis are one step angrier; buses and trucks like long blasts, small cars short taps.
func honk(level: int, delay := 0.0) -> void:
	var v := "horns/%s/" % horn_name()
	var big := model == Model.BUS or model == Model.TRUCK
	var small := model == Model.BUBBLE or model == Model.HATCH
	level = clampi(level + (1 if model == Model.TAXI else 0), 0, 2)
	var tap := v + "tap"
	var lean := v + "long" if Sound.pool_count(v + "long") > 0 else tap
	var keys: Array
	match level:
		0:
			if big and randf() < 0.5:
				keys = [lean]
			else:
				keys = [tap] if randf() < 0.6 else [tap, tap]
		1:
			keys = [tap, tap] if randf() < 0.7 or big else [tap, tap, tap]
		_:
			if small:
				keys = [tap, tap, tap, tap] if randf() < 0.5 else [tap, tap, lean]
			else:
				keys = [tap, tap, lean] if randf() < 0.6 else [lean]
	var pos := global_position + Vector2(length / 2.0, -30.0)
	if not Sound.pool_seq(keys, pos, _horn_pitch, 5.0 if big else 4.0, 0.06, "World", delay):
		Sound.play_at("horn", pos, (0.8 if height > 60.0 else 1.0) * _horn_pitch, -6.0, delay)   # no recording


func roof_y() -> float:
	return position.y - height


func x_min() -> float:
	return position.x


func x_max() -> float:
	return position.x + length


func rect() -> Rect2:
	return Rect2(position.x, roof_y(), length, height)


## The rear end in world space (left for same-direction cars, right for oncoming ones).
func rear_rect() -> Rect2:
	var x := position.x if vx >= 0.0 else position.x + length - REAR_KNOCK
	return Rect2(x, roof_y(), REAR_KNOCK, height)


## Landed on: the driver honks (angrier with every landing while the blinkers still run) and (re)starts the
## hazard blinkers, starting lit. Also run into (Runner death, `with_honk` false: it honks on its own).
func hazard(with_honk := true) -> void:
	if with_honk:
		_honks = _honks + 1 if _hazard > 0.0 else 0
		honk(mini(_honks, 2), 0.05)
	_hazard = HAZARD_TIME
	_hazard_t = 0.0


## Runner crashed into the rear: pop the trunk (tailgate / rear doors) open and throw some cargo out. False if it's already open.
func knock_trunk() -> bool:
	if _trunk_t >= 0.0:
		return false
	_trunk_t = 0.0
	Sound.play_at("trunk_pop", global_position + Vector2(0.0 if vx >= 0.0 else length, -40.0), 1.0, -2.0)
	var origin := _trunk_mouth()
	for i in randi_range(3, 5):
		var kind := randi() % 3                 # 0 suitcase, 1 ball, 2 cardboard box
		if model == Model.TRUCK:
			kind = 2
		var col: Color = [Color(0.3, 0.45, 0.8), Color(0.85, 0.3, 0.25), Color(0.4, 0.65, 0.35),
			Color(0.55, 0.38, 0.6)][randi() % 4]
		if kind == 2:
			col = Color(0.72, 0.54, 0.32)
		_junk.append([origin + Vector2(randf_range(-6, 6), 0), Vector2(randf_range(-260, -60),
			randf_range(-520, -320)), kind, col, 0.0])
	return true


## Where cargo leaves the open trunk (facing frame: rear at x 0, street at y 0).
func _trunk_mouth() -> Vector2:
	match model:
		Model.SEDAN, Model.TAXI, Model.PICKUP:
			return Vector2(PixelArt.snap(length * 0.1), -46)
		Model.BUS:
			return Vector2(20, -60)
		Model.TRUCK:
			return Vector2(4, -60)
	return Vector2(6, -44)


## BUS (type-D school bus) and TRUCK (cab-over semi + trailer) are big vehicles Traffic spawns on purpose
## (set `model` + `preset`); the rest are picked at random by MODEL_WEIGHTS.
enum Model { HATCH, SEDAN, VAN, PICKUP, TAXI, BUBBLE, BUS, TRUCK }
## Random pick weights for the regular cars (same order as Model, HATCH..BUBBLE).
const MODEL_WEIGHTS := [0.22, 0.24, 0.14, 0.13, 0.1, 0.17]
const TAXI_YELLOW := Color(0.96, 0.78, 0.16)
const BUS_YELLOW := Color(0.98, 0.7, 0.08)
const TRAILER_COLORS := [Color(0.9, 0.9, 0.88), Color(0.72, 0.74, 0.78), Color(0.78, 0.24, 0.2),
	Color(0.24, 0.42, 0.7), Color(0.3, 0.56, 0.38), Color(0.92, 0.6, 0.18)]

var model := Model.HATCH
var preset := false                        ## model chosen by Traffic, don't roll one
var height := HEIGHT                       ## roof height for this model (roof_y/rect follow it)
var trailer_color := Color(0.9, 0.9, 0.88)
var _spin := 0.0
var _lights := false

# --- hazard blinkers (landed on) + trunk (rear knocked by a slice) ---
const HAZARD_TIME := 4.0                   ## seconds the blinkers run after a landing
const HAZARD_PERIOD := 0.5                 ## one on/off blink
const TRUNK_OPEN_TIME := 0.24              ## lid swing (back-out ease, so it overshoots and settles)
const REAR_KNOCK := 36.0                   ## px of the car's rear end a slice must touch
const JUNK_GRAVITY := 1500.0
const JUNK_LIFE := 1.8
var _hazard := 0.0                         ## blinker time left
var _hazard_t := 0.0
var _trunk_t := -1.0                       ## < 0 = closed, else seconds since knocked open
var _junk: Array = []                      ## [pos, vel, kind, colour, age] in the car's facing frame

# --- drawing layers: the body repaints only when its look changes, the wheels (a few textured rects) every
# frame, the junk while it flies. Each layer sits at the whole-pixel snap offset, so nothing repaints just
# because the car moved.
enum Layer { BODY, WHEELS, JUNK }
var _layers: Array[CarLayer] = []
var _ci: CanvasItem                        ## layer being painted
var _wheels: Array = []                    ## [centre, r art px, r px] recorded by the body for the wheel layer
var _body_key: Array = []
var _junk_shown := false


func _enter_tree() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST    # wheels are atlas textures (PixelArt.alloy_wheel)
	_lights = TimeOfDay.lights_on()
	if not preset:
		var r := randf() * 1.0                  # global rng: Traffic's spawn sequence stays the same
		var acc := 0.0
		for i in MODEL_WEIGHTS.size():
			acc += MODEL_WEIGHTS[i]
			if r < acc or i == MODEL_WEIGHTS.size() - 1:
				model = i as Model
				break
	match model:
		Model.TAXI:
			color = TAXI_YELLOW
		Model.BUS:
			color = BUS_YELLOW
		Model.TRUCK:
			trailer_color = TRAILER_COLORS[randi() % TRAILER_COLORS.size()]
	match model:
		Model.VAN: height = VAN_HEIGHT
		Model.BUS: height = BUS_HEIGHT
		Model.TRUCK: height = TRUCK_HEIGHT
		_: height = HEIGHT


## Something outside changed a state var and asked for a redraw (sprite dashboard): repaint every layer.
func _draw() -> void:
	_body_key = []
	for c in _layers:
		c.queue_redraw()


func _update_layers() -> void:
	var snap := Vector2(position.round().x - position.x, 0.0)
	for c in _layers:
		c.position = snap
	var key := [vx >= 0.0, _hazard_on(), _trunk_p(), _lights, length, height, color, trailer_color, model]
	if key != _body_key:
		_body_key = key
		_layers[Layer.BODY].queue_redraw()
	_layers[Layer.WHEELS].queue_redraw()
	if _junk_shown or not _junk.is_empty():
		_layers[Layer.JUNK].queue_redraw()
	_junk_shown = not _junk.is_empty()


class CarLayer extends Node2D:
	var car: Car
	var layer := 0

	func _draw() -> void:
		car._paint(self, layer)


func _process(delta: float) -> void:
	_spin += absf(vx) * delta / 10.0       # local space is mirrored for oncoming cars
	_hazard = maxf(_hazard - delta, 0.0)
	_hazard_t += delta
	if _trunk_t >= 0.0:
		_trunk_t += delta
	for j in _junk:                        # facing frame: car speed is already "baked in" while airborne
		j[4] += delta
		j[1].y += JUNK_GRAVITY * delta
		j[0] += j[1] * delta
		if j[0].y >= -4.0:                 # hit the street: bounce, then lie still in world space
			if not _clattered:
				_clattered = true
				Sound.play_at("clatter", global_position + Vector2(0.0 if vx >= 0.0 else length, -10.0), 1.0, -4.0)
			j[0].y = -4.0
			j[1] = Vector2(-absf(vx), -j[1].y * 0.3 if j[1].y > 120.0 else 0.0)
	_junk = _junk.filter(func(j: Array) -> bool: return j[4] < JUNK_LIFE)
	_car_sound()
	_update_layers()


## Engine pitch follows the car's speed, plus a fake Doppler shift: higher while closing in on the camera
## centre, lower once past it. Hazard blinkers tick-tock.
func _car_sound() -> void:
	var on := _hazard_on()
	if on != _blink_was and _hazard > 0.0:
		Sound.play_at("tick", global_position + Vector2(length / 2.0, -20.0), 1.0 if on else 0.78, -12.0, 0.0, 0.0)
	_blink_was = on
	if _engine == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var scroll: float = get_tree().current_scene.get("scroll_speed") if get_tree().current_scene else 0.0
	var dx := position.x + length / 2.0 - cam.get_screen_center_position().x
	var radial := (vx - scroll) * dx / (absf(dx) + 160.0)    # > 0 receding from the listener
	var base := 0.75 + absf(vx) / 1100.0 if height > 60.0 else 0.8 + absf(vx) / 900.0
	_engine.pitch_scale = base / (1.0 + radial / 5000.0)


## Cabin outline as rear-bottom, rear-top, front-top, front-bottom (local px, front at +x), and pane count.
## Every model's roof reaches -height so standing on it lines up with roof_y.
func _cabin(L: float) -> Array:
	var h := -height
	var f := func(k: float) -> float: return PixelArt.snap(L * k)
	match model:
		Model.SEDAN, Model.TAXI:
			return [Vector2(f.call(0.2), -40), Vector2(f.call(0.3), h), Vector2(f.call(0.6), h), Vector2(f.call(0.74), -40), 2]
		Model.VAN:
			return [Vector2(f.call(0.03), -40), Vector2(f.call(0.03), h), Vector2(f.call(0.8), h), Vector2(f.call(0.93), -40), 3]
		Model.PICKUP:
			return [Vector2(f.call(0.42), -40), Vector2(f.call(0.42), h), Vector2(f.call(0.64), h), Vector2(f.call(0.78), -40), 1]
		Model.BUBBLE:
			return [Vector2(f.call(0.14), -40), Vector2(f.call(0.26), h), Vector2(f.call(0.58), h), Vector2(f.call(0.8), -40), 2]
		_:
			return [Vector2(f.call(0.06), -40), Vector2(f.call(0.06), h), Vector2(f.call(0.74) - 18, h), Vector2(f.call(0.74), -40), 2]


static func _edge_x(a: Vector2, b: Vector2, y: float) -> float:
	if is_equal_approx(a.y, b.y):
		return a.x
	return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))


## Car models drawn in 2px "pixels" from a shared lower body + a per-model cabin, front at +x, mirrored
## for oncoming cars. Windows/pillars/door seams derive from the cabin outline. Headlight beams glow
## when lamps are on.
func _paint(ci: CanvasItem, layer: int) -> void:
	_ci = ci
	var L := PixelArt.snap(length)
	var face := 1.0 if vx >= 0.0 else -1.0
	ci.draw_set_transform(Vector2(0.0 if face > 0.0 else L, 0), 0.0, Vector2(face, 1.0))
	match layer:
		Layer.BODY:
			_wheels.clear()
			_paint_body(L)
		Layer.WHEELS:                             # drawn over the body, like before (nothing after them overlaps)
			for w: Array in _wheels:
				PixelArt.alloy_wheel(ci, w[0], w[1], _spin * 10.0 / w[2])
		Layer.JUNK:
			_draw_junk()


func _paint_body(L: float) -> void:
	if model == Model.BUS:
		_draw_bus(L)
		return
	if model == Model.TRUCK:
		_draw_truck(L)
		return
	var outline := PixelArt.OUTLINE
	var dark := color.darkened(0.3)
	var light := color.lightened(0.25)
	var cab := _cabin(L)
	var rb: Vector2 = cab[0]
	var rt: Vector2 = cab[1]
	var ft: Vector2 = cab[2]
	var fb: Vector2 = cab[3]
	var panes: int = cab[4]

	_ci.draw_rect(Rect2(4, -4, L - 8, 6), Color(0, 0, 0, 0.35))                              # ground shadow
	# cabin silhouette (bubble: rounded roof), outlined on the 2 px grid
	var shell := PackedVector2Array([rb, rt, ft, fb])
	if model == Model.BUBBLE:
		shell = PackedVector2Array()
		var c := Vector2((rb.x + fb.x) * 0.5, -40)
		var rx := (fb.x - rb.x) * 0.5
		for k in 13:
			var a := PI + PI * k / 12.0
			shell.append(c + Vector2(cos(a) * rx, sin(a) * (height - 40)))
	PixelArt.poly_outlined(_ci, shell, color.darkened(0.08), outline)
	var hy := -height + 2.0                                                              # roof highlight row
	var hs := PixelArt._span(shell, hy + 1.0)
	_ci.draw_rect(Rect2(PixelArt.snap(hs.x) + 4, hy, PixelArt.snap(hs.y) - PixelArt.snap(hs.x) - 8, 2), light)
	# lower body with stepped corners
	_ci.draw_rect(Rect2(2, -42, L - 4, 32), outline)
	_ci.draw_rect(Rect2(0, -38, L, 26), outline)
	_ci.draw_rect(Rect2(4, -40, L - 8, 28), color)
	_ci.draw_rect(Rect2(2, -36, L - 4, 22), color)
	_ci.draw_rect(Rect2(4, -40, L - 8, 2), light)                                            # shoulder line
	_ci.draw_rect(Rect2(2, -20, L - 4, 6), dark)                                             # sill
	_ci.draw_rect(Rect2(0, -16, L, 4), Color(0.12, 0.12, 0.14))                              # bumper line
	# windows: band between the cabin's rear and front edges, split into panes by pillars
	var glass := Color(0.55, 0.72, 0.84) if not _lights else Color(0.28, 0.34, 0.5)
	var yt := -height + 6.0
	var yb := -42.0
	var lt := _edge_x(rb, rt, yt) + 4.0
	var lb := _edge_x(rb, rt, yb) + 4.0
	var rtx := _edge_x(fb, ft, yt) - 4.0
	var rbx := _edge_x(fb, ft, yb) - 4.0
	if model == Model.BUBBLE:                                                            # follow the dome
		var s := PixelArt._span(shell, yt)
		lt = s.x + 6.0
		rtx = s.y - 6.0
	for k in panes:
		var x0 := PixelArt.snap(lerpf(lb, rbx, float(k) / panes)) + (2.0 if k > 0 else 0.0)
		var x1 := PixelArt.snap(lerpf(lb, rbx, float(k + 1) / panes)) - (2.0 if k < panes - 1 else 0.0)
		var p := PackedVector2Array([
			Vector2(x0 if k > 0 else lb, yb), Vector2(x0 if k > 0 else lt, yt),
			Vector2(x1 if k < panes - 1 else rtx, yt), Vector2(x1 if k < panes - 1 else rbx, yb)])
		PixelArt.poly(_ci, p, glass)
		if k > 0:
			_ci.draw_rect(Rect2(x0 - 2, -40, 2, 24), dark)                                       # door seam
			_ci.draw_rect(Rect2(x0 + 6, -34, 6, 2), dark)                                        # handle
	var gx := PixelArt.snap(lerpf(lb, rbx, 0.7))
	PixelArt.line(_ci, Vector2(gx, yb - 2), Vector2(gx + 6, yt + 2), Color(1, 1, 1, 0.45))  # glare
	_draw_extras(L, outline, dark, light, rb)
	_draw_trunk(L, rt, rb, shell)
	_draw_lights(L, -36, -36, 8 if model != Model.VAN else 16)
	for wx in [PixelArt.snap(L * 0.2), PixelArt.snap(L * 0.78)]:
		_draw_wheel(wx, 12.0, light)


## Head light at the front (+x) at head_y, tail light at the rear; beams + tail glow when lamps are on.
func _draw_lights(L: float, head_y: float, tail_y: float, tail_h: float) -> void:
	var head := Color(1.0, 0.95, 0.7) if not _lights else Color(2.2, 2.1, 1.6)
	var tail := Color(0.85, 0.15, 0.12) if not _lights else Color(2.0, 0.3, 0.2)
	_ci.draw_rect(Rect2(L - 6, head_y, 6, 6), head)
	_ci.draw_rect(Rect2(0, tail_y, 4, tail_h), tail)
	if _lights:
		_ci.draw_polygon(PackedVector2Array([Vector2(L, head_y), Vector2(L + 150, head_y - 10), Vector2(L + 150, 2),
			Vector2(L, head_y + 6)]), PackedColorArray([Color(1.6, 1.5, 1.1, 0.35), Color(1.6, 1.5, 1.1, 0.0),
			Color(1.6, 1.5, 1.1, 0.0), Color(1.6, 1.5, 1.1, 0.35)]))
		_ci.draw_circle(Vector2(-2, tail_y + 4), 9.0, Color(2.0, 0.2, 0.1, 0.18))
	# hazard blinkers: amber under the head and tail lights
	var fy := head_y + 6.0
	var ry := tail_y + tail_h
	if _hazard_on():
		var amber := Color(1.0, 0.62, 0.12) * (1.9 if _lights else 1.35)
		_ci.draw_rect(Rect2(L - 6, fy, 6, 4), amber)
		_ci.draw_rect(Rect2(0, ry, 4, 4), amber)
		var glow := Color(1.8, 1.0, 0.2, 0.28 if _lights else 0.18)                       # FX: glow exempt
		_ci.draw_circle(Vector2(L, fy + 2), 12.0, glow)
		_ci.draw_circle(Vector2(0, ry + 2), 12.0, glow)
	else:
		var dim := Color(0.55, 0.36, 0.12)
		_ci.draw_rect(Rect2(L - 6, fy, 6, 4), dim)
		_ci.draw_rect(Rect2(0, ry, 4, 4), dim)


func _hazard_on() -> bool:
	return _hazard > 0.0 and fmod(_hazard_t, HAZARD_PERIOD) < HAZARD_PERIOD * 0.55


## Trunk open progress 0 -> ~1.1 -> 1 (back-out ease), 0 while closed.
func _trunk_p() -> float:
	if _trunk_t < 0.0:
		return 0.0
	var t := minf(_trunk_t / TRUNK_OPEN_TIME, 1.0) - 1.0
	return 1.0 + 2.7 * t * t * t + 1.7 * t * t


## Open trunk per model (nothing while closed): dark cavity + the lid/hatch/tailgate/doors swung open.
## Regular cars only; bus/truck call it with their own rear door shapes via the model match.
func _draw_trunk(L: float, rt := Vector2.ZERO, rb := Vector2.ZERO, shell := PackedVector2Array()) -> void:
	if _trunk_t < 0.0:
		return
	var p := _trunk_p()
	var cavity := Color(0.08, 0.07, 0.1)
	match model:
		Model.SEDAN, Model.TAXI:                                                         # deck lid lifts
			var hinge := Vector2(PixelArt.snap(rb.x) - 2, -42)
			var lid := hinge.x - 4.0
			_ci.draw_rect(Rect2(4, -42, lid, 6), cavity)
			var a := deg_to_rad(78.0) * p
			PixelArt.limb(_ci, hinge, hinge + Vector2(-cos(a), -sin(a)) * lid, color, 4.0)
		Model.PICKUP:                                                                    # tailgate drops
			var hinge := Vector2(6, -16)
			_ci.draw_rect(Rect2(4, -44, 6, 28), cavity)
			var a := deg_to_rad(90.0) * minf(p, 1.0)
			PixelArt.limb(_ci, hinge, hinge + Vector2(0, -28).rotated(-a), color.darkened(0.1), 4.0)
		Model.VAN:                                                                       # barn doors swing out
			var top := -height + 6.0
			_ci.draw_rect(Rect2(2, top, 8, height - 22), cavity)
			var w := PixelArt.snap(22.0 * sin(PI / 2.0 * minf(p, 1.0)))
			if w > 0.0:
				PixelArt.box(_ci, Rect2(-w, top, w, height - 24), color.darkened(0.1))
				_ci.draw_rect(Rect2(-w + 4, top + 4, maxf(w - 8, 2), 12), _glass())
		Model.BUS:                                                                       # emergency door swings open
			_ci.draw_rect(Rect2(8, -88, 26, 70), cavity)
			var w := maxf(PixelArt.snap(26.0 * cos(PI / 2.0 * minf(p, 1.0) * 0.85)), 4.0)
			PixelArt.box(_ci, Rect2(8 - w + 4, -88, w, 70), color.darkened(0.15))
		Model.TRUCK:                                                                     # trailer doors swing out
			var top := -height + 2.0
			_ci.draw_rect(Rect2(4, top, 8, height - 32), cavity)
			var w := PixelArt.snap(30.0 * sin(PI / 2.0 * minf(p, 1.0)))
			if w > 0.0:
				PixelArt.box(_ci, Rect2(-w, top, w, height - 34), trailer_color.darkened(0.12))
				_ci.draw_rect(Rect2(-w + 4, top + 6, 2, height - 46), trailer_color.darkened(0.35))  # lock bar
		_:                                                                               # hatch swings up on the roof hinge
			# Side view: the rear face is edge-on, so the body keeps its side panel. What shows is the lid
			# (rear glass + lower panel) lifted about the roof hinge on a gas strut, and a thin sliver of
			# interior along the cabin's rear edge and the body's rear where the lid used to sit.
			var hinge: Vector2
			var sill: Vector2                                                        # glass bottom
			var seal := PackedVector2Array()                                         # cabin rear edge, hinge down
			if model == Model.BUBBLE:
				for k in range(4, -1, -1):
					seal.append((shell[k] + Vector2(4, 2 if k > 0 else 0)).snapped(Vector2(2, 2)))
			else:
				seal.append(Vector2(PixelArt.snap(rt.x) + 4, -height + 4))
				seal.append(Vector2(PixelArt.snap(rb.x) + 4, -40))
			hinge = seal[0]
			sill = seal[seal.size() - 1]
			var foot := Vector2(2, -20)
			var inside := Color(0.2, 0.2, 0.26)
			for i in seal.size() - 1:                                                # opening sliver
				PixelArt.line(_ci, seal[i], seal[i + 1], inside, 2.0)
			_ci.draw_rect(Rect2(2, -38, 2, 18), inside)
			var a := deg_to_rad(100.0 if model == Model.HATCH else 80.0) * p
			var s1 := hinge + (sill - hinge).rotated(a)
			var s2 := hinge + (foot - hinge).rotated(a)
			PixelArt.line(_ci, Vector2(PixelArt.snap(maxf(rb.x, 8.0)) + 2, -40), s1.lerp(s2, 0.3),
				Color(0.62, 0.63, 0.68), 2.0)                                            # gas strut
			PixelArt.line(_ci, hinge, s1, cavity, 8.0)                              # outline, then fill
			PixelArt.line(_ci, s1, s2, cavity, 8.0)
			PixelArt.line(_ci, s1, s2, color, 4.0)
			PixelArt.line(_ci, hinge, s1, _glass(), 4.0)


## Cargo thrown out of a knocked trunk (facing frame), blinking out at the end of its life.
func _draw_junk() -> void:
	for j in _junk:
		var age: float = j[4]
		if age > JUNK_LIFE - 0.4 and int(age * 16.0) % 2 == 0:
			continue
		var c: Vector2 = (j[0] as Vector2).snapped(Vector2(2, 2))
		var col: Color = j[3]
		match j[2]:
			0:                                                                           # suitcase + handle
				PixelArt.box(_ci, Rect2(c + Vector2(-8, -10), Vector2(16, 10)), col)
				_ci.draw_rect(Rect2(c + Vector2(-4, -14), Vector2(8, 2)), PixelArt.OUTLINE)
				_ci.draw_rect(Rect2(c + Vector2(-8, -6), Vector2(16, 2)), col.darkened(0.3))
			1:                                                                           # ball
				PixelArt.disc(_ci, c + Vector2(0, -6), 8.0, PixelArt.OUTLINE)
				PixelArt.disc(_ci, c + Vector2(0, -6), 6.0, col)
				_ci.draw_rect(Rect2(c + Vector2(-2, -10), Vector2(2, 2)), col.lightened(0.5))
			_:                                                                           # cardboard box
				PixelArt.box(_ci, Rect2(c + Vector2(-8, -12), Vector2(16, 12)), col)
				_ci.draw_rect(Rect2(c + Vector2(-2, -12), Vector2(4, 12)), col.lightened(0.2))  # tape


## Alloy wheel of radius r (px) touching the ground at x, like the kid's FamilyCar: a rounded arch cut
## into the body (lit fender lip, outline, liner, well shadow; closed flat at `bottom`, the body's lower
## edge) then the tyre + 5-spoke rim. lip.a == 0 -> no arch (truck trailer axles hang below the body).
func _draw_wheel(x: float, r: float, lip: Color, bottom := -10.0) -> void:
	var c := Vector2(PixelArt.snap(x), -r)
	if lip.a > 0.0:
		PixelArt.arch(_ci, c, r + 8.0, bottom, lip)
		PixelArt.arch(_ci, c, r + 6.0, bottom, PixelArt.OUTLINE)
		PixelArt.arch(_ci, c, r + 4.0, bottom, Color(0.18, 0.18, 0.21))
		PixelArt.arch(_ci, c, r + 2.0, bottom, Color(0.09, 0.09, 0.11))
	_wheels.append([c, r / PixelArt.PX, r])                  # the rolling tyre + rim: wheel layer


## Model-specific details on top of the body.
func _draw_extras(L: float, outline: Color, dark: Color, light: Color, rb: Vector2) -> void:
	match model:
		Model.TAXI:                                                                      # checker band
			var x := 6.0
			var k := 0
			while x < L - 10.0:
				_ci.draw_rect(Rect2(x, -30 if k % 2 == 0 else -28, 4, 2), Color(0.1, 0.1, 0.1))
				x += 4.0
				k += 1
		Model.PICKUP:                                                                    # open bed with rails
			_ci.draw_rect(Rect2(4, -46, rb.x - 6, 6), outline)
			_ci.draw_rect(Rect2(6, -44, rb.x - 10, 2), light)
			_ci.draw_rect(Rect2(6, -42, rb.x - 10, 2), dark)
			_ci.draw_rect(Rect2(4, -46, 4, 30), outline)                                     # tailgate edge
		Model.VAN:                                                                       # sliding-door rail
			_ci.draw_rect(Rect2(PixelArt.snap(L * 0.3), -42, PixelArt.snap(L * 0.3), 2), dark)
		Model.BUBBLE:                                                                    # round headlight bezel
			_ci.draw_rect(Rect2(L - 10, -38, 10, 10), outline)


## Body box from roof (-h) down to bottom_y, x 0..L, with stepped (rounded) top corners and an outline.
func _body(L: float, h: float, bottom_y: float, fill: Color) -> void:
	var o := PixelArt.OUTLINE
	_ci.draw_rect(Rect2(4, -h, L - 8, h + bottom_y), o)
	_ci.draw_rect(Rect2(2, -h + 2, L - 4, h + bottom_y - 2), o)
	_ci.draw_rect(Rect2(0, -h + 4, L, h + bottom_y - 4), o)
	_ci.draw_rect(Rect2(6, -h + 2, L - 12, h + bottom_y - 4), fill)
	_ci.draw_rect(Rect2(4, -h + 4, L - 8, h + bottom_y - 6), fill)
	_ci.draw_rect(Rect2(2, -h + 6, L - 4, h + bottom_y - 8), fill)


func _glass() -> Color:
	return Color(0.55, 0.72, 0.84) if not _lights else Color(0.28, 0.34, 0.5)


## Type-D (flat-nose) school bus, front at +x: yellow box, black rub rails, a row of split windows,
## rear emergency door, front entry door, folded stop arm, roof warning lights.
func _draw_bus(L: float) -> void:
	var o := PixelArt.OUTLINE
	var h := height
	var light := color.lightened(0.3)
	var dark := color.darkened(0.25)
	var black := Color(0.1, 0.1, 0.12)
	var glass := _glass()
	_ci.draw_rect(Rect2(4, -4, L - 8, 6), Color(0, 0, 0, 0.35))                              # ground shadow
	_body(L, h, -14, color)
	_ci.draw_rect(Rect2(8, -h + 2, L - 16, 2), light)                                        # roof highlight
	_ci.draw_rect(Rect2(4, -h + 6, L - 8, 2), Color(0.95, 0.92, 0.84))                       # white roof edge
	_ci.draw_rect(Rect2(2, -18, L - 4, 4), dark)                                             # skirt shade
	for y in [-56, -40, -26]:                                                            # rub rails
		_ci.draw_rect(Rect2(2, y, L - 4, 4), black)
	# side windows (upper pane slides down: split line), between rear door and entry door
	var x := 42.0
	while x + 26.0 <= L - 70.0:
		_ci.draw_rect(Rect2(x - 2, -88, 30, 30), o)
		_ci.draw_rect(Rect2(x, -86, 26, 26), glass)
		_ci.draw_rect(Rect2(x, -76, 26, 2), o)
		_ci.draw_rect(Rect2(x + 4, -84, 2, 6), Color(1, 1, 1, 0.4))                          # glare
		x += 32.0
	# rear emergency door
	_ci.draw_rect(Rect2(6, -90, 30, 74), o)
	_ci.draw_rect(Rect2(8, -88, 26, 70), color)
	_ci.draw_rect(Rect2(10, -86, 22, 26), glass)
	_ci.draw_rect(Rect2(28, -50, 4, 2), black)                                               # handle
	# front entry door: two tall glass leaves
	var dx := L - 64.0
	_ci.draw_rect(Rect2(dx, -90, 30, 74), o)
	_ci.draw_rect(Rect2(dx + 2, -88, 12, 70), glass)
	_ci.draw_rect(Rect2(dx + 16, -88, 12, 70), glass)
	_ci.draw_rect(Rect2(dx + 2, -54, 26, 2), o)
	# windshield edge at the flat nose
	_ci.draw_rect(Rect2(L - 16, -90, 12, 34), o)
	_ci.draw_rect(Rect2(L - 14, -88, 8, 30), glass)
	# folded stop arm (red octagon) behind the driver
	var sc := Vector2(L - 80, -46)
	PixelArt.disc(_ci, sc, 10.0, o)
	PixelArt.disc(_ci, sc, 8.0, Color(0.82, 0.12, 0.1))
	_ci.draw_rect(Rect2(sc.x - 4, sc.y - 2, 8, 2), Color(0.95, 0.95, 0.95))
	# roof warning lights (amber + red pairs at each end)
	var warn := (1.0 if not _lights else 1.8) * (1.6 if _hazard_on() else 1.0)
	for wx in [10.0, L - 22.0]:
		_ci.draw_rect(Rect2(wx - 2, -h + 8, 16, 8), o)
		_ci.draw_rect(Rect2(wx, -h + 10, 6, 4), Color(0.95, 0.55, 0.1) * warn)
		_ci.draw_rect(Rect2(wx + 8, -h + 10, 6, 4), Color(0.9, 0.15, 0.1) * warn)
	_ci.draw_rect(Rect2(-2, -18, 6, 6), black)                                               # bumpers
	_ci.draw_rect(Rect2(L - 4, -20, 6, 8), black)
	_draw_trunk(L)
	_draw_lights(L, -36, -36, 10)
	for wx in [PixelArt.snap(L * 0.17), PixelArt.snap(L * 0.8)]:
		_draw_wheel(wx, 14.0, light, -12.0)


## Cab-over semi with a box trailer, front at +x. The cab's roof fairing reaches the trailer roof so the
## whole length is one standable roof (roof_y). Trailer colour per truck; the cab uses `color`.
func _draw_truck(L: float) -> void:
	var o := PixelArt.OUTLINE
	var h := height
	var black := Color(0.1, 0.1, 0.12)
	var steel := Color(0.58, 0.6, 0.64)
	var tc := trailer_color
	var T := L - 76.0                                                                    # trailer length
	var c0 := L - 70.0                                                                   # cab rear
	_ci.draw_rect(Rect2(4, -4, L - 8, 6), Color(0, 0, 0, 0.35))                              # ground shadow
	_ci.draw_rect(Rect2(8, -32, L - 24, 8), black)                                           # chassis rails
	# trailer box
	_ci.draw_rect(Rect2(0, -h, T, h - 28), o)
	_ci.draw_rect(Rect2(2, -h + 2, T - 4, h - 32), tc)
	_ci.draw_rect(Rect2(2, -h + 2, T - 4, 2), tc.lightened(0.25))
	_ci.draw_rect(Rect2(2, -34, T - 4, 4), tc.darkened(0.3))
	var rx := 26.0
	while rx < T - 8.0:                                                                  # corrugation ribs
		_ci.draw_rect(Rect2(rx, -h + 6, 2, h - 42), tc.darkened(0.14))
		rx += 24.0
	_ci.draw_rect(Rect2(2, -72, T - 4, 8), color)                                            # livery stripes
	_ci.draw_rect(Rect2(2, -60, T - 4, 2), color.darkened(0.2))
	_ci.draw_rect(Rect2(4, -h + 6, 4, h - 40), tc.darkened(0.3))                             # rear door hinge
	for k in range(int(T / 48.0)):                                                       # clearance lamps
		_ci.draw_rect(Rect2(10 + k * 48, -h + 4, 4, 2), Color(0.95, 0.6, 0.15) * (1.8 if _lights else 1.0))
	# underride guard + landing gear
	_ci.draw_rect(Rect2(6, -28, 4, 14), o)
	_ci.draw_rect(Rect2(2, -16, 18, 4), o)
	_ci.draw_rect(Rect2(T - 64, -28, 4, 20), steel)
	_ci.draw_rect(Rect2(T - 68, -10, 12, 4), o)
	# exhaust stack in the gap behind the cab
	_ci.draw_rect(Rect2(T, -h + 6, 6, 82), o)
	_ci.draw_rect(Rect2(T + 2, -h + 8, 2, 78), steel)
	# cab box + roof fairing up to the trailer roof
	_ci.draw_rect(Rect2(c0, -82, 70, 64), o)
	_ci.draw_rect(Rect2(c0 + 2, -80, 66, 60), color)
	PixelArt.poly_outlined(_ci, PackedVector2Array([Vector2(c0, -h), Vector2(L - 28, -h),
		Vector2(L - 4, -80), Vector2(c0, -80)]), color.darkened(0.1))
	_ci.draw_rect(Rect2(c0 + 4, -h + 2, L - c0 - 36, 2), color.lightened(0.25))             # fairing highlight
	_ci.draw_rect(Rect2(c0 + 2, -80, 66, 2), color.lightened(0.25))
	_ci.draw_rect(Rect2(L - 32, -78, 28, 26), o)                                             # side window
	_ci.draw_rect(Rect2(L - 30, -76, 24, 22), _glass())
	_ci.draw_rect(Rect2(L - 26, -74, 2, 8), Color(1, 1, 1, 0.4))
	_ci.draw_rect(Rect2(L - 36, -78, 2, 56), color.darkened(0.3))                            # door seam
	_ci.draw_rect(Rect2(L - 44, -62, 6, 2), black)                                           # handle
	_ci.draw_rect(Rect2(L - 40, -88, 4, 10), o)                                              # mirror arm + mirror
	_ci.draw_rect(Rect2(L - 2, -84, 4, 16), o)
	for gy in [-48, -44, -40]:                                                           # grille slats
		_ci.draw_rect(Rect2(L - 6, gy, 6, 2), color.darkened(0.4))
	_ci.draw_rect(Rect2(L - 40, -22, 14, 4), steel)                                          # step
	_ci.draw_rect(Rect2(L - 8, -24, 10, 10), steel)                                          # bumper
	_ci.draw_rect(Rect2(L - 8, -16, 10, 2), o)
	_draw_lights(L, -32, -44, 10)
	for wx in [28.0, 56.0]:                                                              # trailer tandem
		_draw_wheel(wx, 12.0, Color(0, 0, 0, 0))
	_ci.draw_rect(Rect2(72, -26, 4, 18), black)                                              # mud flap
	_draw_trunk(L)
	for wx in [T - 22.0, T + 2.0]:                                                       # drive axles
		_draw_wheel(wx, 12.0, Color(0, 0, 0, 0))
	_draw_wheel(L - 20.0, 12.0, color.lightened(0.25), -18.0)                            # steer axle under the cab

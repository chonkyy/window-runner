class_name Bird
extends Node2D
## Pixel-art bird (17x16 art px at 2x). position = feet. Perched on a wire (default) or flying mid-air (flying = true).
## Either kind must be sliced or dodged; touching an unsliced bird ends the run.

const SIZE := Vector2(34, 32)                ## hitbox = sprite size
const DEATH_TIME := 0.22                   ## length of the pop effect

var alive := true
var bounces := true                        ## stomping a bird bounces you and kills it
var hop_mult := 2.0
var flying := false
var vx := 0.0                              ## flying: world velocity (negative = toward the runner)
var base_y := 0.0                          ## flying: mean height
var bob_amp := 0.0
var _t := 0.0
var _dead_t := 0.0
var _feathers: Array[Vector2] = []         ## outward directions of the pop effect


var _peck_off := 0.0
var _flutter: AudioStreamPlayer2D
var _coo_t := 0.0


func _ready() -> void:
	add_to_group("birds")
	_t = randf() * TAU
	_peck_off = randf() * 3.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if flying:                                   # incoming flyers flap audibly
		_flutter = Sound.emitter(self, "flutter", -13.0, Vector2(0, -16), 1000.0)
	_coo_t = randf_range(2.0, 14.0)


func roof_y() -> float:
	return global_position.y - SIZE.y


func x_min() -> float:
	return global_position.x - SIZE.x / 2.0


func x_max() -> float:
	return global_position.x + SIZE.x / 2.0


func rect() -> Rect2:
	return Rect2(global_position - Vector2(SIZE.x / 2.0, SIZE.y), SIZE)


func _physics_process(delta: float) -> void:
	_t += delta
	if not alive:
		_dead_t += delta
	if flying and alive:
		position.x += vx * delta
		position.y = base_y + sin(_t * 3.0) * bob_amp
	elif alive:
		_coo_t -= delta
		if _coo_t <= 0.0:
			_coo_t = randf_range(6.0, 16.0) / float(TimeOfDay.p().birds)
			if Sound.near(global_position, 700.0):
				Sound.play_at("coo", global_position + Vector2(0, -16), randf_range(0.9, 1.1), -10.0)
	queue_redraw()


func slice() -> void:
	alive = false
	remove_from_group("birds")
	if _flutter:
		_flutter.stop()
	Sound.play_at("feathers", global_position + Vector2(0, -16), 1.0, -4.0)
	Sound.bird_voice(global_position + Vector2(0, -16), randf_range(0.94, 1.12))
	for k in 7:
		_feathers.append(Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.0))
	queue_redraw()
	get_tree().create_timer(DEATH_TIME).timeout.connect(queue_free)
	var f := Feathers.new()
	f.cols = [PIGEON.G, PIGEON.g, PIGEON.W, PIGEON.W, PIGEON.b]
	f.carry = float(get_tree().current_scene.get("scroll_speed")) * 0.85 if get_tree().current_scene else 0.0
	f.position = position + Vector2(0, -SIZE.y / 2.0)    # same parent space as the bird
	get_parent().add_child(f)


## Feathers that burst out, then drift down rocking like falling leaves. Separate node so it outlives the
## bird. `carry` gives them a forward drift (fading) so they stay in view of the scrolling camera a while.
## Each feather is an ASCII sprite (vaned contour feathers with a light shaft and split barbs, or a fluffy
## down feather), pre-rotated on the art grid (`_frame`, ROT_STEP increments) instead of rotating the
## drawing, so the pixels stay crisp. Every feather has its own lifetime, so they fade out one by one.
class Feathers extends Node2D:
	const LIFE_MIN := 0.9                 ## per-feather lifetime range (s); the node frees after the last
	const LIFE_MAX := 2.6
	const FADE := 0.36                    ## stepped fade-out at the end of each feather's life
	const ROT_STEP := PI / 12.0           ## 15 deg frames
	const ROT_FRAMES := 3                 ## -3..3 steps (+-45 deg)
	const OUTLINE := Color(0.07, 0.06, 0.11)
	## K outline, l light vane, m shaded vane, q shaft (runs out past the vane as the bare quill).
	## Drawn tip-right, the shaft through the middle row, notches split the barbs.
	const SHAPES := [
		[   # long contour feather
			"....KKKKK.......",
			"..KKlllllKKK....",
			".KllllllllllKKK.",
			"qqqqqqqqqqqqqqqK",
			".KmmmmmKmmmmmK..",
			"..KmmmK.KKKKK...",
			"...KKK..........",
		],
		[   # curved feather, tip sweeping up
			"............KKK.",
			"..........KKlllK",
			"......KKKKllllK.",
			"...KKKlllllqqK..",
			"qqqqqqqqqqqmK...",
			"...KmmmKmmmK....",
			"....KKK.KKK.....",
		],
		[   # small feather
			"..KKK.....",
			".KlllKKK..",
			"qqqqqqqqqK",
			".KmmKmmK..",
			"..KK.KK...",
		],
	]
	const SHAPE_WEIGHTS := [0.4, 0.3, 0.3]
	static var _frames := {}

	var cols: Array = []
	var carry := 0.0
	var _items: Array[Dictionary] = []
	var _t := 0.0
	var _end := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var t: Color = TimeOfDay.tint()                 # half-undo the world tint so night feathers still read
		self_modulate = Color(1.0 / sqrt(t.r), 1.0 / sqrt(t.g), 1.0 / sqrt(t.b))
		for k in randi_range(14, 18):
			var r := randf()
			var shape := 0
			while shape < SHAPE_WEIGHTS.size() - 1 and r >= SHAPE_WEIGHTS[shape]:
				r -= SHAPE_WEIGHTS[shape]
				shape += 1
			var life := randf_range(LIFE_MIN, LIFE_MAX)
			_end = maxf(_end, life)
			_items.append({
				"pos": Vector2.ZERO,
				"vel": Vector2.from_angle(randf() * TAU) * randf_range(140.0, 340.0) + Vector2(0, -90),
				"phase": randf() * TAU,
				"freq": randf_range(2.6, 4.2),            # rocking speed
				"amp": randf_range(0.5, 0.85),            # rocking angle (rad)
				"spin": randf_range(-1.6, 1.6),           # extra tilt from the burst, settles out
				"fall": randf_range(35.0, 60.0),
				"shape": shape,
				"flip": 1.0 if randf() < 0.5 else -1.0,
				"life": life,
				"col": cols[k % cols.size()],
			})

	func _process(delta: float) -> void:
		_t += delta
		if _t >= _end:
			queue_free()
			return
		var drag := exp(-5.0 * delta)
		var drift := carry * exp(-0.6 * _t)                         # forward drift, dies out
		for it in _items:
			var v: Vector2 = it.vel
			v.x *= drag
			v.y = move_toward(v.y * drag, it.fall, 140.0 * delta)       # settle to a slow fall
			it.vel = v
			# falling-leaf rock: glides sideways in the direction it is swinging
			var sway: float = cos(_t * it.freq + it.phase) * 46.0
			it.pos += v * delta + Vector2((drift + sway) * delta, 0)
		queue_redraw()

	func _draw() -> void:
		for it in _items:
			var left: float = it.life - _t
			if left <= 0.0:
				continue
			var a := clampf(left / FADE, 0.0, 1.0)
			a = ceilf(a * 3.0) / 3.0                                        # stepped fade (3 levels)
			var rot: float = sin(_t * it.freq + it.phase) * it.amp + it.spin * exp(-3.0 * _t)
			var step := clampi(roundi(rot / ROT_STEP), -ROT_FRAMES, ROT_FRAMES)
			var fy := 1.0
			if step > 0:                     # the +steps sample less cleanly: mirror the matching -step frame
				step = -step
				fy = -1.0
			var tex := _frame(it.shape, it.col, step)
			var size := Vector2(tex.get_size()) * PixelArt.PX
			draw_set_transform((it.pos as Vector2).snapped(Vector2(2, 2)), 0.0, Vector2(it.flip, fy))
			draw_texture_rect(tex, Rect2(-size / 2.0, size), false, Color(1, 1, 1, a))
		draw_set_transform(Vector2.ZERO)

	## Feather sprite `shape` in colour `col`, rotated by step * ROT_STEP on the art grid (nearest
	## sampling per art pixel, even canvas so it centres on the 2 px grid). Cached.
	static func _frame(shape: int, col: Color, step: int) -> ImageTexture:
		var key := "%d|%s|%d" % [shape, col.to_html(), step]
		if _frames.has(key):
			return _frames[key]
		var shaft := col.darkened(0.42) if col.get_luminance() > 0.4 else col.lightened(0.4)
		var pal := {"K": OUTLINE, "l": col.lightened(0.22), "m": col.darkened(0.2), "q": shaft}
		var rows: Array = SHAPES[shape]
		var w: int = rows[0].length()
		var h := rows.size()
		var n := int(ceil(sqrt(w * w + h * h))) + 2
		n += n % 2
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ca := cos(step * ROT_STEP)
		var sa := sin(step * ROT_STEP)
		var sc := Vector2(w, h) / 2.0
		var dc := Vector2(n, n) / 2.0
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5) - dc
				var s := Vector2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca) + sc     # inverse rotation
				var sx := int(floorf(s.x))
				var sy := int(floorf(s.y))
				if sx < 0 or sy < 0 or sx >= w or sy >= h:
					continue
				var ch: String = rows[sy][sx]
				if ch != ".":
					img.set_pixel(x, y, pal[ch])
		var tex := ImageTexture.create_from_image(img)
		_frames[key] = tex
		return tex


## 17x16 art px at 2x (= SIZE), drawn facing right and flipped to face the runner. Gray pigeons,
## chunky and high-contrast (dark outline, bright belly, black wing bars). They perch (and peck by
## tilting) or fly (two wing frames).
const PERCHED := [
	"...........KKK...",
	"..........KGGGK..",
	"..........KGEGKYY",
	"..........KNNGK..",
	".....KKKKKNNNNK..",
	"...KKgggGGNNNWK..",
	"..KggggGGGGWWWWK.",
	".KgbbggGGGWWWWWK.",
	"KggggggGGGWWWWWK.",
	"KgggbbGGGGWWWWWK.",
	"KKgggGGGGWWWWWK..",
	".KKKgGGGWWWWKK...",
	"...KKKKKKKKKK....",
	".......Y..Y......",
	".......Y..Y......",
	"......YY.YY......",
]
const WINGS_UP := [
	".................",
	"....KK...........",
	"....KgK..........",
	"....KggK.........",
	".....KggK........",
	".....KgggK.......",
	"......KgggK.KKK..",
	"KK....KGGGKKGGGK.",
	"KgK.KKGGGGGGGGEKY",
	".KgKGGGGGGGGGGGYY",
	"..KGGWWWWWWWWGGK.",
	"...KKWWWWWWWWKK..",
	".....KKKKKKKK....",
	".................",
	".................",
	".................",
]
const WINGS_DOWN := [
	".................",
	".................",
	".................",
	".................",
	".................",
	".................",
	"............KKK..",
	"KK....KKKKKKGGGK.",
	"KgKKKKGGGGGGGGEKY",
	".KgGGGGGGGGGGGGYY",
	"..KGGWWWWWWWWGGK.",
	"...KKgggggWWWKK..",
	"....KgggggKKK....",
	"....KggggK.......",
	"...KgggK.........",
	"...KKKK..........",
]
const PIGEON := {"K": Color(0.07, 0.06, 0.11), "G": Color(0.64, 0.66, 0.82), "g": Color(0.43, 0.45, 0.63),
	"b": Color(0.14, 0.13, 0.22), "W": Color(0.97, 0.97, 1.0), "N": Color(0.2, 0.85, 0.66),
	"E": Color(1.0, 0.45, 0.1), "Y": Color(1.0, 0.55, 0.18)}
func _draw() -> void:
	var col: Color = PIGEON.G
	if alive:
		_draw_sprite()
		return
	var k := clampf(_dead_t / DEATH_TIME, 0.0, 1.0)
	var mid := Vector2(0, -SIZE.y / 2.0)
	draw_circle(mid, SIZE.x * (0.4 + k), Color(1, 1, 1, 0.8 * (1.0 - k)))              # flash
	for f in _feathers:
		var a := mid + f * (14.0 + 46.0 * k)
		PixelArt.line(self, a, a + f * 8.0, Color(col.r, col.g, col.b, 1.0 - k))         # feathers


func _draw_sprite() -> void:
	var key: String
	var rows: Array
	var pal: Dictionary
	var tilt := 0.0
	if flying:
		var up := fmod(_t * 9.0, 2.0) < 1.0
		key = "pigeon_up" if up else "pigeon_down"
		rows = WINGS_UP if up else WINGS_DOWN
		pal = PIGEON
	else:
		key = "pigeon"
		rows = PERCHED
		pal = PIGEON
		if fmod(_t * 0.7 + _peck_off, 3.0) > 2.75:                  # peck: tip forward now and then
			tilt = 0.35
	var tex := PixelArt.texture(key, PackedStringArray(rows), pal)
	var face_left := not flying or vx < 0.0
	var off := global_position.round() - global_position
	var sx := -1.0 if face_left else 1.0
	draw_set_transform(off, tilt * sx, Vector2(sx, 1.0))
	var r := Rect2(-SIZE.x / 2.0, -SIZE.y, SIZE.x, SIZE.y)
	draw_texture_rect(tex, r, false)
	draw_set_transform(Vector2.ZERO)

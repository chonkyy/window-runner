class_name Backdrop
extends CanvasLayer
## Sky gradient, sun/moon/stars, drifting clouds and three parallax layers per biome (far = hazy, near =
## saturated), coloured by the time-of-day preset and greyed by the rain. Lives on its own canvas layer so the
## world's CanvasModulate doesn't tint it twice. Game calls scroll(view_x, world_x) every frame.
## Each Biome.Kind has its own layer set (BIOME_LAYERS) inside a CanvasGroup; at a biome boundary the new set
## fades in over the old one (only the one or two sets in use exist). Layer chunks draw once (static canvas
## items) and are recycled as the camera moves. All art on the 4 px backdrop grid (PX).

static var VIEW := View.BASE                ## screen size, set in _ready (wide phones: View.w() > 1280)
const GROUND_Y := 612.0                   ## layer bases (hidden behind the sidewalk)
const PX := 4.0                           ## backdrop "pixel" size

## Layer configs. `id` seeds the drawing, so a layer shared by two biomes (the far skyline) is identical in
## both and doesn't flicker in a cross-fade. style: drawer (Chunk._draw). col: preset colour key.
## haze: how much the layer's real-colour props (houses, fences) fade into the haze colour.
const SKY_FAR := {"id": 0, "style": "city", "factor": 0.08, "w": Vector2(48, 120), "h": Vector2(150, 380),
	"gap": 24.0, "win": Vector2(4, 4), "col": "far", "haze": 0.45}
const SKY_MID := {"id": 1, "style": "city", "factor": 0.2, "w": Vector2(64, 150), "h": Vector2(110, 300),
	"gap": 40.0, "win": Vector2(4, 8), "col": "mid", "haze": 0.3}
const SKY_NEAR := {"id": 2, "style": "city", "factor": 0.42, "w": Vector2(80, 180), "h": Vector2(70, 230),
	"gap": 70.0, "win": Vector2(8, 8), "col": "near", "haze": 0.15}
const TREELINE := {"id": 7, "style": "trees", "factor": 0.2, "col": "mid", "haze": 0.3}
const HOUSES := {"id": 8, "style": "houses", "factor": 0.42, "col": "near", "haze": 0.12}

const BIOME_LAYERS := [                   ## indexed by Biome.Kind, far to near
	[SKY_FAR, SKY_MID, SKY_NEAR],         # CITY
	[SKY_FAR, TREELINE, HOUSES],          # SUBURB
]
const HAZE_STRENGTH := [0.55, 0.4, 0.22]  ## fog band in front of each layer

var seed_value := 0                       ## round seed (Game): every round's scenery differs
var _sets := {}                           ## Biome.Kind -> CanvasGroup of that biome's layers
var _clouds: Clouds
var _view_x := 0.0


## Rain greys and darkens a sky/backdrop colour (rain 0..1).
static func wet(c: Color, rain: float) -> Color:
	if rain <= 0.0:
		return c
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l * 1.06, c.a), 0.5 * rain).darkened(0.2 * rain)


func _ready() -> void:
	VIEW = View.size()
	layer = -10
	var p := TimeOfDay.p()
	var rain := Weather.rain

	var sky := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, wet(p.sky_top, rain))
	g.set_color(1, wet(p.sky_bottom, rain))
	g.add_point(0.55, wet(p.sky_mid, rain))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	sky.texture = tex
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.size = Backdrop.VIEW
	add_child(sky)

	var sky_fx := SkyFx.new()
	sky_fx.preset = p
	sky_fx.rain = rain
	add_child(sky_fx)

	_clouds = Clouds.new()
	var cc: Color = wet(p.cloud, rain * 1.4)
	cc.a = lerpf(p.cloud.a, 0.9, rain)
	_clouds.color = cc
	_clouds.count = 9 + int(12 * rain)
	add_child(_clouds)


func scroll(view_x: float, world_x: float) -> void:
	_view_x = view_x
	_clouds.scroll(view_x)
	var b := Biome.blend_at(world_x)
	var from := int(b.x)
	var to := int(b.y)
	for k in _sets.keys():
		if k != from and k != to:
			(_sets[k] as Node).queue_free()
			_sets.erase(k)
	var a := _layer_set(from)
	a.self_modulate.a = 1.0
	a.scroll(view_x)
	if to != from:                               # new biome fades in on top of the old one
		var s := _layer_set(to)
		move_child(s, -1)
		s.self_modulate.a = Cabin._smooth(b.z)
		s.scroll(view_x)


func _layer_set(kind: int) -> LayerSet:
	if _sets.has(kind):
		return _sets[kind]
	var s := build_set(kind, seed_value)
	add_child(s)
	s.scroll(_view_x)
	_sets[kind] = s
	return s


## A biome's layers + haze bands for the current phase and weather (also used by the sprite dashboard).
static func build_set(kind: int, seed_value: int) -> LayerSet:
	var p := TimeOfDay.p()
	var rain := Weather.rain
	var s := LayerSet.new()
	var cfgs: Array = BIOME_LAYERS[kind]
	for i in cfgs.size():
		var L := Skyline.new()
		L.cfg = cfgs[i]
		L.seed_value = seed_value
		L.color = wet(p[cfgs[i].col], rain)
		L.green = wet(p.green, rain)
		L.tint = TimeOfDay.tint()
		L.window_lit = p.windows * (1.0 + 0.5 * rain)            # gloomy: more lights on
		L.haze = wet(p.haze, rain)
		s.add_child(L)
		s.layers.append(L)
		var hz := Haze.new()
		hz.color = L.haze
		hz.strength = minf(HAZE_STRENGTH[i] * (1.0 + 0.4 * rain), 0.8)
		s.add_child(hz)
	return s


## One biome's layers + haze bands, composited together so a cross-fade fades the whole picture.
## (Stays a CanvasGroup even when not fading: drawing the layers directly blends the haze slightly differently.)
class LayerSet extends CanvasGroup:
	var layers: Array[Skyline] = []

	func scroll(view_x: float) -> void:
		for L in layers:
			L.scroll(view_x)


## Sun or moon with glow rings, plus stars. Rain hides the stars and veils the sun (heavy rain: gone).
class SkyFx extends Node2D:
	var preset: Dictionary
	var rain := 0.0

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var stars: float = preset.stars * (1.0 - rain)
		for i in int(160 * stars):
			var pos := Vector2(rng.randf() * Backdrop.VIEW.x, rng.randf() * Backdrop.VIEW.y * 0.6).snapped(Vector2(2, 2))
			var a := rng.randf_range(0.3, 1.0) * stars
			draw_rect(Rect2(pos, Vector2(2, 2) * (2.0 if rng.randf() < 0.08 else 1.0)), Color(1, 1, 0.95, a))
		var veil := 1.0 - 0.85 * rain
		if rain >= 1.0:
			return
		var c: Vector2 = preset.sun_pos * Backdrop.VIEW
		var r: float = preset.sun_r
		var col: Color = preset.sun
		for k in [3.2, 2.2, 1.5]:
			draw_circle(c, r * k, Color(col.r, col.g, col.b, 0.07 * veil))
		_pixel_disc(c, r, Color(col, veil))
		if preset.moon:
			for crater in [Vector2(-8, 4), Vector2(6, 10), Vector2(-2, -10)]:
				draw_rect(Rect2((c + crater).snapped(Vector2(PX, PX)), Vector2(PX, PX)), Color(col.darkened(0.15), veil))

	## Disc made of PX-sized rows (chunky pixel look).
	func _pixel_disc(c: Vector2, r: float, col: Color) -> void:
		var y := -r
		while y < r:
			var half := sqrt(maxf(r * r - (y + PX * 0.5) * (y + PX * 0.5), 0.0))
			half = roundf(half / PX) * PX
			draw_rect(Rect2((c + Vector2(-half, y)).snapped(Vector2(PX, PX)), Vector2(half * 2.0, PX)), col)
			y += PX


## Slow drifting pixel clouds, two copies of one strip for wrap-around. Rain: more of them, lower, wider.
class Clouds extends Node2D:
	var color := Color.WHITE
	var count := 9
	const STRIP := 2560.0

	func scroll(cam_x: float) -> void:
		var ms := Engine.get_physics_frames() * 1000.0 / 60.0 if Runner.immortal else float(Time.get_ticks_msec())
		position.x = -fposmod(cam_x * 0.03 + ms * 0.004, STRIP)    # bench: frame clock, repeatable
		position.x = roundf(position.x)

	func _draw() -> void:
		if color.a <= 0.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var clouds := []
		var overcast := count > 9
		for i in count:
			var w := rng.randf_range(80.0, 220.0) * (1.6 if overcast else 1.0)
			clouds.append([rng.randf() * STRIP, rng.randf_range(20.0, 220.0 if overcast else 300.0), w])
		for copy in 2:
			for cl in clouds:
				_cloud(Vector2(cl[0] + copy * STRIP, cl[1]), cl[2], rng)

	func _cloud(at: Vector2, w: float, rng: RandomNumberGenerator) -> void:
		var rows := int(w / 40.0) + 2
		for r in rows:
			var k := float(r) / rows
			var rw := w * (0.45 + 0.55 * sin(k * PI))
			var off := rng.randf_range(-10.0, 10.0)
			draw_rect(Rect2(Vector2(at.x - rw * 0.5 + off, at.y + r * PX * 2.0).snapped(Vector2(PX, PX)),
				Vector2(rw, PX * 2.0).snapped(Vector2(PX, PX))), color)
		draw_rect(Rect2(Vector2(at.x - w * 0.4, at.y + rows * PX * 2.0).snapped(Vector2(PX, PX)),
			Vector2(w * 0.8, PX).snapped(Vector2(PX, PX))), color.darkened(0.12))


## Vertical fog gradient over the lower part of the screen.
class Haze extends Node2D:
	var color := Color.WHITE
	var strength := 0.4

	func _draw() -> void:
		var top := GROUND_Y - 260.0
		var clear := Color(color, 0.0)
		var fog := Color(color, strength)
		draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(Backdrop.VIEW.x, top), Vector2(Backdrop.VIEW.x, GROUND_Y),
			Vector2(0, GROUND_Y)]), PackedColorArray([clear, clear, fog, fog]))


## One parallax layer: a row of chunk nodes, each drawing its part of the layer once.
class Skyline extends Node2D:
	const CHUNK := 1024.0
	var cfg: Dictionary
	var seed_value := 0
	var color := Color.GRAY                ## the layer's preset colour (far/mid/near)
	var green := Color.DARK_GREEN          ## preset hills/trees colour
	var tint := Color.WHITE                ## world tint: lights real-colour props (houses, shops) like the world
	var window_lit := 0.0
	var haze := Color.WHITE
	var _chunks: Dictionary = {}

	## Real-world colour lit like the world and faded into this layer's haze.
	func real(c: Color) -> Color:
		return (c * Color(tint.r, tint.g, tint.b)).lerp(haze, cfg.haze)

	func scroll(cam_x: float) -> void:
		var off: float = cam_x * cfg.factor
		position.x = -roundf(off)
		var first := int(floorf(off / CHUNK)) - 1
		var last := int(floorf((off + Backdrop.VIEW.x) / CHUNK))
		for i in range(first, last + 1):
			if not _chunks.has(i):
				var c := Chunk.new()
				c.idx = i
				c.owner_layer = self
				c.position.x = i * CHUNK
				add_child(c)
				_chunks[i] = c
		for i in _chunks.keys():
			if i < first:
				(_chunks[i] as Node2D).queue_free()
				_chunks.erase(i)

	class Chunk extends Node2D:
		var idx := 0
		var owner_layer: Skyline
		var L: Skyline

		## Deterministic 0..1 for (a, b) in this layer + round.
		func _h(a: int, b: int) -> float:
			return float(absi(hash(Vector4i(L.cfg.id, L.seed_value, a, b))) % 100000) / 100000.0

		func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
			draw_rect(Rect2(Vector2(x, y).snapped(Vector2(PX, PX)), Vector2(w, h).snapped(Vector2(PX, PX))), c)

		func _draw() -> void:
			L = owner_layer
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(L.cfg.id, idx, L.seed_value))
			match L.cfg.style:
				"city":
					var x := 0.0
					while x < CHUNK:
						var w := snappedf(rng.randf_range(L.cfg.w.x, L.cfg.w.y), PX * 2.0)
						var h := snappedf(rng.randf_range(L.cfg.h.x, L.cfg.h.y), PX * 2.0)
						_building(rng, x, w, h)
						x += w + snappedf(rng.randf_range(0.0, L.cfg.gap), PX)
				"trees":
					_treeline()
				"houses":
					var x := 0.0
					while x < CHUNK:
						var w := snappedf(rng.randf_range(96.0, 152.0), PX * 2.0)
						_house(rng, x, w)
						var gap := snappedf(rng.randf_range(28.0, 72.0), PX)
						_yard(rng, x + w, gap)
						x += w + gap

		# --- CITY: skyline blocks -----------------------------------------------------------------------

		func _building(rng: RandomNumberGenerator, x: float, w: float, h: float) -> void:
			var cfg := L.cfg
			var shade := rng.randf_range(-0.06, 0.06)
			var col := Color(L.color.r + shade, L.color.g + shade, L.color.b + shade * 1.2)
			var top := GROUND_Y - h
			draw_rect(Rect2(x, top, w, h), col)
			draw_rect(Rect2(x + w - PX * 2.0, top, PX * 2.0, h), col.darkened(0.12))     # side shade
			draw_rect(Rect2(x - PX, top, w + PX * 2.0, PX), col.lightened(0.1))           # roof ledge
			match rng.randi() % 5:
				0:                                                                       # stepped top
					var sw := snappedf(w * 0.5, PX)
					draw_rect(Rect2(x + snappedf(w * 0.2, PX), top - PX * 6.0, sw, PX * 6.0), col)
				1:                                                                       # antenna
					var ax := x + snappedf(w * rng.randf_range(0.2, 0.8), PX)
					draw_rect(Rect2(ax, top - PX * 12.0, PX, PX * 12.0), col.darkened(0.1))
					if L.window_lit > 0.0:
						draw_rect(Rect2(ax - PX * 0.5, top - PX * 13.0, PX * 2.0, PX * 2.0), Color(1.0, 0.25, 0.2))
				2:                                                                       # water tower
					var tx := x + snappedf(w * 0.25, PX)
					draw_rect(Rect2(tx, top - PX * 9.0, PX * 7.0, PX * 6.0), col.darkened(0.08))
					draw_rect(Rect2(tx + PX, top - PX * 3.0, PX, PX * 3.0), col.darkened(0.15))
					draw_rect(Rect2(tx + PX * 5.0, top - PX * 3.0, PX, PX * 3.0), col.darkened(0.15))
				3:                                                                       # AC boxes
					draw_rect(Rect2(x + PX * 2.0, top - PX * 3.0, PX * 5.0, PX * 3.0), col.darkened(0.06))
			# windows
			var ww: float = cfg.win.x
			var wh: float = cfg.win.y
			var near_layer: bool = cfg.id != 0
			var gx := ww + PX * (3.0 if near_layer else 2.0)
			var gy := wh + PX * (3.0 if near_layer else 2.0)
			var dark := col.darkened(0.22)
			var day := col.lightened(0.12)
			var lit_roll := rng.randf() < 0.85                                             # some buildings fully dark
			var wy := top + PX * 3.0
			while wy + wh < GROUND_Y - PX * 6.0:
				var wx := x + PX * 2.0
				while wx + ww < x + w - PX * 2.0:
					var c := dark if L.window_lit > 0.0 else (day if rng.randf() < 0.3 else dark)
					if lit_roll and rng.randf() < L.window_lit:
						c = Color(1.0, 0.82, 0.48).lerp(Color(0.8, 0.9, 1.0), rng.randf() * 0.3)
						c = c.lerp(L.haze, 0.1 if near_layer else 0.35)
					draw_rect(Rect2(wx, wy, ww, wh), c)
					wx += gx
				wy += gy

		# --- SUBURB: tree line + houses ----------------------------------------------------------------------

		## Continuous row of round tree crowns over the rooftops, the odd water tower or steeple poking out.
		func _treeline() -> void:
			var x0 := position.x
			var col := L.green.lerp(L.color, 0.4)
			var cell := 36.0
			var j := int(floorf(x0 / cell)) - 1
			while j * cell < x0 + CHUNK + cell:
				var cx := snappedf(j * cell - x0, PX)
				var roll := _h(j, 21)
				if roll < 0.035:
					var leg := L.color.darkened(0.08)
					_r(cx - 12.0, GROUND_Y - 150.0, PX, 150.0, leg)
					_r(cx + 12.0, GROUND_Y - 150.0, PX, 150.0, leg)
					_r(cx - 20.0, GROUND_Y - 184.0, 44.0, 36.0, L.color)
					PixelArt.disc(self, Vector2(cx + 2.0, GROUND_Y - 184.0), 22.0, L.color, PX)
				elif roll < 0.055:
					_r(cx - 12.0, GROUND_Y - 150.0, 24.0, 150.0, L.color)
					PixelArt.poly(self, PackedVector2Array([Vector2(cx - 12.0, GROUND_Y - 150.0), Vector2(cx, GROUND_Y - 210.0),
						Vector2(cx + 12.0, GROUND_Y - 150.0)]), L.color, PX)
				var r := snappedf(22.0 + _h(j, 22) * 14.0, PX)
				var cy := GROUND_Y - snappedf(84.0 + _h(j, 23) * 40.0, PX)
				var c := col.darkened(0.08 * float(j % 2))
				_r(cx - r * 0.8, cy, r * 1.6, GROUND_Y - cy, c)
				PixelArt.disc(self, Vector2(cx, cy), r, c, PX)
				PixelArt.disc(self, Vector2(cx - PX * 2.0, cy - PX * 2.0), r - PX * 3.0, c.lightened(0.05), PX)
				j += 1

		const HOUSE_WALLS := [Color(0.9, 0.86, 0.76), Color(0.72, 0.82, 0.86), Color(0.92, 0.8, 0.62),
			Color(0.78, 0.86, 0.72), Color(0.86, 0.72, 0.7), Color(0.66, 0.66, 0.72)]
		const ROOFS := [Color(0.5, 0.22, 0.2), Color(0.3, 0.3, 0.36), Color(0.42, 0.3, 0.24), Color(0.26, 0.34, 0.4)]

		## Detached house: walls, gable or hip roof (shaded half), chimney, windows (lit at night), door,
		## sometimes a garage and a gable window.
		func _house(rng: RandomNumberGenerator, x: float, w: float) -> void:
			var wall: Color = L.real(HOUSE_WALLS[rng.randi() % HOUSE_WALLS.size()])
			var roof: Color = L.real(ROOFS[rng.randi() % ROOFS.size()])
			var wall_h := snappedf(rng.randf_range(52.0, 76.0), PX)
			var roof_h := snappedf(rng.randf_range(28.0, 44.0), PX)
			var wt := GROUND_Y - wall_h
			var mid := x + snappedf(w * 0.5, PX)
			# chimney first (the roof covers its foot)
			if rng.randf() < 0.6:
				var chx := x + snappedf(w * rng.randf_range(0.6, 0.78), PX)
				_r(chx, wt - roof_h * 0.75 - 12.0, 12.0, roof_h, L.real(Color(0.55, 0.32, 0.26)))
				_r(chx - PX, wt - roof_h * 0.75 - 16.0, 20.0, PX, L.real(Color(0.4, 0.4, 0.42)))
			_r(x, wt, w, wall_h, wall)
			_r(x + w - PX * 2.0, wt, PX * 2.0, wall_h, wall.darkened(0.12))
			var hip := rng.randf() < 0.35
			var apex_l := Vector2(mid - (snappedf(w * 0.25, PX) if hip else 0.0), wt - roof_h)
			var apex_r := Vector2(mid + (snappedf(w * 0.25, PX) if hip else 0.0), wt - roof_h)
			PixelArt.poly(self, PackedVector2Array([Vector2(x - 8.0, wt + PX), apex_l, Vector2(mid, wt - roof_h),
				Vector2(mid, wt + PX)]), roof.lightened(0.06), PX)
			PixelArt.poly(self, PackedVector2Array([Vector2(mid, wt + PX), Vector2(mid, wt - roof_h), apex_r,
				Vector2(x + w + 8.0, wt + PX)]), roof.darkened(0.08), PX)
			_r(x - 8.0, wt + PX, w + 16.0, PX, roof.darkened(0.3))                         # eave shadow
			if not hip and rng.randf() < 0.5:                                                 # gable window
				_window(mid - 6.0, wt - roof_h * 0.55, 12.0, 12.0, wall, rng)
			# ground floor: door + windows (+ garage)
			var garage := w >= 128.0 and rng.randf() < 0.5
			var door_x := x + 12.0 if not garage else x + w - 28.0
			_r(door_x, GROUND_Y - 32.0, 16.0, 32.0, L.real(Color(0.4, 0.26, 0.2)))
			_r(door_x + 12.0, GROUND_Y - 18.0, PX, PX, L.real(Color(0.9, 0.8, 0.4)))
			if garage:
				_r(x + 8.0, GROUND_Y - 36.0, 52.0, 36.0, wall.darkened(0.08))
				var gy := GROUND_Y - 32.0
				while gy < GROUND_Y:
					_r(x + 12.0, gy, 44.0, PX, wall.darkened(0.2))
					gy += 8.0
			var wx := door_x + 28.0 if not garage else x + 68.0
			while wx + 20.0 < (x + w - 8.0 if not garage else door_x - 6.0):
				_window(wx, wt + 12.0, 20.0, 20.0, wall, rng)
				wx += 32.0

		func _window(x: float, y: float, w: float, h: float, wall: Color, rng: RandomNumberGenerator) -> void:
			var frame := wall.lightened(0.15)
			_r(x - PX, y - PX, w + PX * 2.0, h + PX * 2.0, frame)
			var glass := L.real(Color(0.32, 0.42, 0.52))
			if rng.randf() < L.window_lit * 1.5:
				glass = Color(1.0, 0.82, 0.5).lerp(L.haze, 0.08)
			_r(x, y, w, h, glass)
			if L.window_lit <= 0.0:
				_r(x, y, PX * 2.0, PX, glass.lightened(0.35))
			_r(x + snappedf(w * 0.5, PX) - PX * 0.5, y, PX, h, frame)
			_r(x, y + snappedf(h * 0.5, PX) - PX * 0.5, w, PX, frame)

		## Between houses: a front-yard tree, a hedge or a picket fence.
		func _yard(rng: RandomNumberGenerator, x: float, w: float) -> void:
			var roll := rng.randf()
			var leaf := L.real(Color(0.28, 0.5, 0.26))
			if roll < 0.5:
				var cx := x + snappedf(w * 0.5, PX)
				var r := snappedf(rng.randf_range(16.0, 26.0), PX)
				_r(cx - PX, GROUND_Y - 40.0, PX * 2.0, 40.0, L.real(Color(0.36, 0.26, 0.18)))
				PixelArt.disc(self, Vector2(cx, GROUND_Y - 40.0 - r * 0.6), r, leaf.darkened(0.1), PX)
				PixelArt.disc(self, Vector2(cx - PX, GROUND_Y - 44.0 - r * 0.6), r - PX * 2.0, leaf, PX)
			elif roll < 0.75:
				_r(x, GROUND_Y - 20.0, w, 20.0, leaf.darkened(0.15))
				_r(x, GROUND_Y - 20.0, w, PX, leaf)
			else:
				var white := L.real(Color(0.92, 0.92, 0.9))
				_r(x, GROUND_Y - 16.0, w, PX, white)
				var fx := x
				while fx < x + w:
					_r(fx, GROUND_Y - 20.0, PX, 20.0, white)
					fx += 8.0

class_name PixelArt
extends RefCounted
## Builds ImageTextures from ASCII grids (one char = one art pixel, '.' = transparent). Stand-in for
## Aseprite sheets: swap a texture() call for a load() and the drawing code stays the same.
## Draw with a node whose texture_filter is NEAREST.

static var _cache: Dictionary = {}


## rows: equal-length strings. palette: char -> Color. silhouette: every opaque pixel white (for rim light).
static func texture(key: String, rows: PackedStringArray, palette: Dictionary, silhouette := false) -> ImageTexture:
	var ck := key + ("#sil" if silhouette else "")
	if _cache.has(ck):
		return _cache[ck]
	var w := rows[0].length()
	var img := Image.create(w, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		if row.length() != w:
			push_error("PixelArt '%s': row %d is %d wide, expected %d" % [key, y, row.length(), w])
		for x in mini(row.length(), w):
			var ch := row[x]
			if ch == ".":
				continue
			if not palette.has(ch):
				push_error("PixelArt '%s': no colour for '%s'" % [key, ch])
				continue
			img.set_pixel(x, y, Color.WHITE if silhouette else palette[ch])
	var tex := ImageTexture.create_from_image(img)
	_cache[ck] = tex
	return tex


## Snap v to a grid of size g.
static func snap(v: float, g: float = 2.0) -> float:
	return roundf(v / g) * g


# --- Procedural drawing on the art grid -------------------------------------------------------------
# World sprites use 2 px art pixels (PX) and 1-art-pixel (2 px) outlines. These helpers keep code-drawn
# shapes on that grid: every edge lands on a multiple of g and diagonals step in whole art pixels,
# never 1 px. Pass g = 4 etc. for close-ups drawn at a bigger pixel size (Cabin).

const PX := 2.0                            ## world art pixel, screen px
const OUTLINE := Color(0.07, 0.06, 0.09)   ## shared sprite outline


## Filled rect snapped to the grid, with a 1-art-pixel outline around (outside) it.
static func box(ci: CanvasItem, r: Rect2, fill: Color, outline := OUTLINE, g := PX) -> void:
	r = Rect2(r.position.snapped(Vector2(g, g)), r.size.snapped(Vector2(g, g)).max(Vector2(g, g)))
	ci.draw_rect(r.grow(g), outline)
	ci.draw_rect(r, fill)


## Thick line stepped through grid cells (w = brush size in px, a multiple of g). Endpoints snap to the grid.
static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w := PX, g := PX) -> void:
	var ga := (a / g).round()
	var gb := (b / g).round()
	var steps := int(maxf(absf(gb.x - ga.x), absf(gb.y - ga.y)))
	var off := floorf(w / (2.0 * g)) * g            # brush offset so the square stays on the grid
	for i in steps + 1:
		var p := ga.lerp(gb, float(i) / steps).round() if steps > 0 else ga
		ci.draw_rect(Rect2(p * g - Vector2(off, off), Vector2(w, w)), col)


## Outlined limb: a w-wide line inside a 1-art-pixel outline.
static func limb(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w := PX, outline := OUTLINE, g := PX) -> void:
	line(ci, a, b, outline, w + 2.0 * g, g)
	line(ci, a, b, col, w, g)


## Disc of grid rows around c (c snaps to a grid point, r to the grid): symmetric, stepped edges.
static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color, g := PX) -> void:
	c = c.snapped(Vector2(g, g))
	r = snap(r, g)
	var y := -r
	while y < r:
		var yc := y + g * 0.5
		var half := snap(sqrt(maxf(r * r - yc * yc, 0.0)), g)
		if half > 0.0:
			ci.draw_rect(Rect2(c.x - half, c.y + y, half * 2.0, g), col)
		y += g


## Horizontal span [x0, x1] of convex polygon pts at height y (empty -> x0 > x1).
static func _span(pts: PackedVector2Array, y: float) -> Vector2:
	var x0 := INF
	var x1 := -INF
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if (y < minf(a.y, b.y)) or (y > maxf(a.y, b.y)):
			continue
		var x := a.x if is_equal_approx(a.y, b.y) else lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
		if is_equal_approx(a.y, b.y):
			x0 = minf(x0, minf(a.x, b.x))
			x1 = maxf(x1, maxf(a.x, b.x))
		else:
			x0 = minf(x0, x)
			x1 = maxf(x1, x)
	return Vector2(x0, x1)


## Per grid row of a convex polygon: [y, x0, x1], all on the grid.
static func rows(pts: PackedVector2Array, g: float) -> Array:
	var top := INF
	var bottom := -INF
	for p in pts:
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	var out := []
	var y := snap(top, g)
	while y < snap(bottom, g):
		var s := _span(pts, clampf(y + g * 0.5, top, bottom))
		if s.x <= s.y:
			var x0 := snap(s.x, g)
			var x1 := snap(s.y, g)
			if x1 > x0:
				out.append([y, x0, x1])
		y += g
	return out


## Convex polygon filled in whole grid rows (stepped edges, no 1 px stairs).
static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, g := PX) -> void:
	for r in rows(pts, g):
		ci.draw_rect(Rect2(r[1], r[0], r[2] - r[1], g), col)


## Inner span [x0, x1] of row i of rs (from rows()) inside a 1-cell outline: inset by g from the row's
## own edges and its neighbours', so the outline widens where the edge jumps more than a pixel.
## Top/bottom rows (all outline) -> x0 >= x1.
static func inner_span(rs: Array, i: int, g: float) -> Vector2:
	if i == 0 or i == rs.size() - 1:
		return Vector2.ZERO
	var r: Array = rs[i]
	return Vector2(maxf(r[1], maxf(rs[i - 1][1], rs[i + 1][1])) + g,
		minf(r[2], minf(rs[i - 1][2], rs[i + 1][2])) - g)


## Convex polygon with a 1-art-pixel outline drawn inside its edge. The outline widens where the edge
## jumps more than a pixel between rows, so it never breaks up on shallow slopes.
static func poly_outlined(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline := OUTLINE, g := PX) -> void:
	var rs := rows(pts, g)
	for i in rs.size():
		var r: Array = rs[i]
		ci.draw_rect(Rect2(r[1], r[0], r[2] - r[1], g), outline)
		var s := inner_span(rs, i, g)
		if s.y > s.x:
			ci.draw_rect(Rect2(s.x, r[0], s.y - s.x, g), fill)


const TREAD := Color(0.13, 0.13, 0.16)
const TYRE := Color(0.17, 0.17, 0.2)
const TYRE_HI := Color(0.31, 0.31, 0.35)
const RIM_HI := Color(0.9, 0.91, 0.94)
const RIM_LO := Color(0.46, 0.47, 0.52)
const SPOKE := Color(0.76, 0.77, 0.82)
const SPOKE_DK := Color(0.56, 0.57, 0.62)
const RIM_WINDOW := Color(0.12, 0.12, 0.15)
const CALIPER := Color(0.62, 0.17, 0.14)
const HUB := Color(0.64, 0.65, 0.7)


## Tyre + 5-spoke alloy rim of radius r (art px, centre c in px) on the g-px grid, rolled by `roll`
## (tread notches and spokes turn; shading from the upper left and the brake caliper stay put). Drawn from
## a per-radius atlas of WHEEL_FRAMES roll steps built once (`_wheel_atlas`), so a wheel is one textured
## rect instead of a few hundred; the node must sample NEAREST (Car / FamilyCar set it).
const WHEEL_FRAMES := 360                  ## roll steps per turn (1°: well under a pixel at the rim)
const WHEEL_COLS := 24                     ## atlas layout: frames per row
static var _wheel_atlases: Dictionary = {} ## int(r * 8) -> ImageTexture atlas


static func alloy_wheel(ci: CanvasItem, c: Vector2, r: float, roll: float, g := PX) -> void:
	c = c.snapped(Vector2(g, g))
	var n := int(r)
	var f := int(roundf(fposmod(roll, TAU) / TAU * WHEEL_FRAMES)) % WHEEL_FRAMES
	var s := 2 * n
	var src := Rect2((f % WHEEL_COLS) * s, (f / WHEEL_COLS) * s, s, s)
	ci.draw_texture_rect_region(_wheel_atlas(r), Rect2(c.x - n * g, c.y - n * g, s * g, s * g), src)


## Build every wheel atlas in use up front (Game._ready), so the first car on screen doesn't stall a frame:
## world cars r 6, bus r 7, the kid's FamilyCar r 8. Cached for the whole launch.
static func warm_wheels() -> void:
	for r in [6.0, 7.0, 8.0]:
		_wheel_atlas(r)


static func _wheel_atlas(r: float) -> ImageTexture:
	var key := int(r * 8.0)
	if _wheel_atlases.has(key):
		return _wheel_atlases[key]
	var n := int(r)
	var s := 2 * n
	var img := Image.create(s * WHEEL_COLS, s * ceili(WHEEL_FRAMES / float(WHEEL_COLS)), false, Image.FORMAT_RGBAF)
	img.fill(Color(0, 0, 0, 0))
	for f in WHEEL_FRAMES:
		var ox := (f % WHEEL_COLS) * s + n
		var oy := (f / WHEEL_COLS) * s + n
		var roll := f * TAU / WHEEL_FRAMES
		for j in range(-n, n):
			for i in range(-n, n):
				var col := _wheel_px(Vector2(i + 0.5, j + 0.5), r, roll)
				if col.a > 0.0:
					img.set_pixel(ox + i, oy + j, col)
	var tex := ImageTexture.create_from_image(img)
	_wheel_atlases[key] = tex
	return tex


## Colour of the wheel art pixel at offset p from the centre (transparent outside the tyre).
static func _wheel_px(p: Vector2, r: float, roll: float) -> Color:
	var d := p.length()
	if d > r:
		return Color(0, 0, 0, 0)
	var seg := TAU / 5.0
	var hub := r * 0.275
	var notches := 24.0 if r >= 7.0 else 16.0
	var a := p.angle()
	var ar := fposmod(a - roll, TAU)                                  # rolling frame
	var lit := p.normalized().dot(Vector2(-0.6, -0.8))                # 1 = facing the light
	if d > r - 1.0:                                                   # tread
		return TREAD if int(ar / (TAU / notches)) % 2 == 0 else OUTLINE
	elif d > r - 2.0:                                                 # sidewall
		return TYRE_HI if lit > 0.8 else TYRE
	elif d > r - 3.0:                                                 # rim lip
		return RIM_HI if lit > 0.0 else RIM_LO
	elif d > hub:                                     # spokes (widening outward) / dark windows
		var m := fposmod(ar, seg)
		if minf(m, seg - m) * d < 0.7 + 0.12 * (d - hub):
			return SPOKE if lit > -0.2 else SPOKE_DK
		elif d > r * 0.45 and absf(angle_difference(a, -2.5)) < 0.45:   # caliper behind the rim
			return CALIPER
		return RIM_WINDOW
	elif d > r * 0.125:                                               # hub
		return HUB if lit > -0.2 else SPOKE_DK
	return RIM_HI                                                     # centre cap


## Rounded wheel-arch layer: half disc of radius r (px) over centre c, closed flat at y = bottom (px).
static func arch(ci: CanvasItem, c: Vector2, r: float, bottom: float, col: Color, g := PX) -> void:
	var pts := PackedVector2Array([Vector2(c.x - r, bottom)])
	for k in 13:
		pts.append(c + Vector2.from_angle(PI + k * PI / 12.0) * r)
	pts.append(Vector2(c.x + r, bottom))
	poly(ci, pts, col, g)


## Spoked wheel, all px: dark tyre (outer `tyre` px of r), a `rim` ring, then `inner` (transparent = rim
## all the way in), n spokes rotated by `spin`, 2x2-pixel hub.
static func wheel(ci: CanvasItem, c: Vector2, r: float, tyre: float, rim_w: float, rim: Color, inner: Color,
		spoke: Color, spin: float, n := 3, g := PX) -> void:
	c = c.snapped(Vector2(g, g))
	disc(ci, c, r, OUTLINE, g)
	disc(ci, c, r - tyre, rim, g)
	var reach := r - tyre - g
	if inner.a > 0.0:
		disc(ci, c, r - tyre - rim_w, inner, g)
		reach = r - tyre - rim_w
	for k in n:
		var d := Vector2.from_angle(spin + k * TAU / n)
		line(ci, c + d * g, c + d * reach, spoke, g, g)
	ci.draw_rect(Rect2(c - Vector2(g, g), Vector2(2.0 * g, 2.0 * g)), OUTLINE)
